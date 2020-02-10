#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from nipyapi import canvas
from ..utils import exception_context

QUEUED_MSG_THRESHOLD = 1


def test_data_flowing():
    for pg in canvas.list_all_process_groups():
        if pg.status.name == 'NiFi Flow':
                continue
        assert pg.status.aggregate_snapshot.bytes_in > 0


def test_nifi_bulletins():
    bulletins = [b for b in canvas.get_bulletin_board().bulletin_board.bulletins if b.bulletin]
    with exception_context(bulletins):
        assert [] == \
            ['Bulletin: Time: %s, Level: %s, Source: %s, Node: %s, Message: [%s]' % (
                b.timestamp, b.bulletin.level if b.bulletin else 'UNKNOWN',
                b.bulletin.source_name if b.bulletin else b.source_id,
                b.node_address, b.bulletin.message if b.bulletin else 'UNKNOWN')
             for b in sorted(bulletins, key=lambda x: x.id)]


def test_nifi_queues():
    assert [] == \
        ['Found queue not empty: %s -> %s, Queued: %s' % (conn.component.source.name, conn.component.destination.name, conn.status.aggregate_snapshot.queued)
         for conn in [x for x in canvas.list_all_connections() if int(x.status.aggregate_snapshot.queued_count.replace(',', '')) > QUEUED_MSG_THRESHOLD]]
