#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Testing NiFi
"""
from datetime import datetime, timedelta
from nipyapi import canvas
from ...labs import exception_context, retry_test
from ...labs.utils import nifi

QUEUED_MSG_THRESHOLD = 1

nifi.set_environment()


def _get_timestamp(time_str, yesterday=False):
    day = datetime.today() - timedelta(days=1 if yesterday else 0)
    return datetime.strptime(day.strftime('%Y-%m-%d') + ' ' + time_str, '%Y-%m-%d %H:%M:%S').timestamp()


def _get_bulletin_timestamp(bulletin):
    time_str = bulletin.timestamp[:8]
    # Assumes time is of current day
    ts = _get_timestamp(time_str)
    if ts > datetime.now().timestamp():
        # Above assumption was incorrect. Use yesterday instead.
        ts = _get_timestamp(time_str, yesterday=True)
    return ts


def test_data_flowing():
    for pg in canvas.list_all_process_groups():
        if pg.status.name == 'NiFi Flow':
            continue
        assert pg.status.aggregate_snapshot.bytes_in > 0


def test_nifi_bulletins(run_id):
    # run_id is the timestamp of the start of this run. Ignore bulletins generated prior to this run start time
    bulletins = [b for b in canvas.get_bulletin_board().bulletin_board.bulletins
                 if b.bulletin and _get_bulletin_timestamp(b.bulletin) > float(run_id)]
    with exception_context(bulletins):
        # Ignore bulletins from Default Atlas Reporting Task to avoid some transient authentication errors
        # Also ignore INFO bulletins.
        assert [] == \
            ['Bulletin: Time: {}, Level: {}, Source: {}, Node: {}, Message: [{}]'.format(
                b.timestamp, b.bulletin.level if b.bulletin else 'UNKNOWN',
                b.bulletin.source_name if b.bulletin else b.source_id,
                b.node_address, b.bulletin.message if b.bulletin else 'UNKNOWN')
             for b in sorted(bulletins, key=lambda x: x.id)
                if not b.bulletin or (b.bulletin.source_name != 'Default Atlas Reporting Task'
                                      and b.bulletin.level != 'INFO')]


@retry_test(max_retries=10, wait_time_secs=5)
def test_nifi_queues():
    assert [] == \
        ['Found queue not empty: {} -> {}, Queued: {}'.format(
            conn.component.source.name, conn.component.destination.name,
            conn.status.aggregate_snapshot.queued)
         for conn in [x for x in canvas.list_all_connections()
                      if int(x.status.aggregate_snapshot.queued_count.replace(',', '')) > QUEUED_MSG_THRESHOLD]]
