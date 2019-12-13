from nipyapi import canvas
from ..utils import exception_context, retry_test

QUEUED_MSG_THRESHOLD = 1

@retry_test(max_retries=120, wait_time_secs=1)
def test_nifi_bulletins():
    bulletins = canvas.get_bulletin_board().bulletin_board.bulletins
    with exception_context(bulletins):
        assert [] == \
            ['Bulletin: %s - %s - %s - %s - %s' % (b.timestamp, b.level, b.source_name, b.node_address, b.message)
             for b in [bulletin.bulletin for bulletin in sorted(bulletins, lambda x, y: cmp(x.id, y.id))]]

def test_nifi_queues():
    assert [] == \
        ['Found queue not empty: %s -> %s, Queued: %s' % (conn.component.source.name, conn.component.destination.name, conn.status.aggregate_snapshot.queued)
         for conn in [x for x in canvas.list_all_connections() if int(x.status.aggregate_snapshot.queued_count.replace(',', '')) > QUEUED_MSG_THRESHOLD]]
