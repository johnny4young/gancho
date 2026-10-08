# Pending board deletions and remote changes

A local board deletion records a tombstone until the sync adapter acknowledges
the remote deletion. While that tombstone exists, both incoming board metadata
and membership carried by a clip must respect the deletion. Otherwise an
in-flight fetch can recreate the board, either with its old metadata or as an
unnamed placeholder.

The GRDB receive paths check the tombstone in the same transaction as the write.
Board metadata is skipped, and membership rebuilds exclude only the deleted
board IDs. Other memberships, including placeholders for genuinely unknown
boards, continue to apply. A fetched page counts rejected board metadata as
`skippedAsStale`; the clip itself can still apply normally.

The public sync protocol and server-wins policy for ordinary board metadata are
unchanged. No schema or permanent deletion history is added. After the adapter
acknowledges deletion and clears the tombstone, this temporary guard no longer
rejects that ID. This does not promise cross-zone ordering after acknowledgement
or retroactively remove boards resurrected before the correction.

`BoardTombstoneTests` covers metadata, membership-only arrivals, combined pages,
preserved unrelated memberships, and the acknowledgement boundary.
