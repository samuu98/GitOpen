final class CommitRequest {

  const CommitRequest({
    required this.message,
    this.amend = false,
    this.signOff = false,
    this.sign = false,
    this.authorName,
    this.authorEmail,
  });
  final String message;
  final bool amend;
  final bool signOff;

  /// When true, the commit is GPG-signed (`git commit -S`). Defaults to false
  /// so existing callers keep their unsigned behaviour.
  final bool sign;
  final String? authorName;
  final String? authorEmail;
}
