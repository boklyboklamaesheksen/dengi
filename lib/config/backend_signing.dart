class BackendSigning {
  static const _secret = String.fromEnvironment('RABOCHIY_SIGNING_SECRET');

  static String get secret {
    if (_secret.isEmpty) {
      throw StateError('RABOCHIY_SIGNING_SECRET is not configured');
    }
    return _secret;
  }
}
