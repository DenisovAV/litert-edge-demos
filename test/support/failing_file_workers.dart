import 'dart:isolate';

/// Worker entry points for `ModelFileOps(worker: …)` that fail the way a
/// real worker can: they run in a real isolate, so the test exercises the
/// real port protocol.

/// An uncaught error in the worker isolate (its `onError` message).
void crashingFileWorker((Object, SendPort) args) =>
    throw StateError('the worker blew up');

/// The worker's own error report, as its generic `catch` sends it.
void erroringFileWorker((Object, SendPort) args) =>
    args.$2.send(('error', 'the worker reported a failure'));

/// The worker exits without sending a result (its `onExit` message only).
void silentFileWorker((Object, SendPort) args) {}
