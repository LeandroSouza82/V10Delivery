// Conditional export of local image helpers. The implementation differs
// between IO (mobile/desktop) and Web targets.
export 'local_image_stub.dart'
    if (dart.library.io) 'local_image_io.dart'
    if (dart.library.html) 'local_image_web.dart';
