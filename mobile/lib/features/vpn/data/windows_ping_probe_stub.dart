/// Web has no raw sockets. The Windows-only provider never calls this on web;
/// the stub keeps the conditional import compilable everywhere.
Stream<int?> windowsPingStream() => Stream<int?>.value(null);
