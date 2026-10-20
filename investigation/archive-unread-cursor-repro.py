"""Exercise the archive scan's SQL boundary with synthetic chat-list keys."""
import sqlite3
import struct


def archive_message_key(peer_id: int) -> bytes:
    return struct.pack('>iHibiqb', 1, 0, 1000, 0, 20, peer_id, 1)


archive_database = sqlite3.connect(':memory:')
archive_database.execute('CREATE TABLE archive_entries (key BLOB PRIMARY KEY, label TEXT)')
archive_database.executemany(
    'INSERT INTO archive_entries VALUES (?, ?)',
    [(archive_message_key(101), 'hidden'), (archive_message_key(100), 'visible unread')],
)
archive_query = 'SELECT label FROM archive_entries WHERE key > ? AND key < ? ORDER BY key DESC LIMIT ?'
original_cursor_result = archive_database.execute(
    archive_query, (b'', archive_message_key(101), 1)
).fetchall()
predecessor_cursor_result = archive_database.execute(
    archive_query, (b'', archive_message_key(100), 1)
).fetchall()
assert original_cursor_result == [('visible unread',)]
assert predecessor_cursor_result == []
print('Exact exclusive cursor: visible unread entry returned')
print('Predecessor plus exclusive cursor: visible unread entry skipped')
print('Synthetic SQL boundary reproduction only; no app database or timing measurement')
