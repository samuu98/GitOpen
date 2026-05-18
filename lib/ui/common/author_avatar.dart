import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';

/// Round avatar in the GitHub style: Gravatar by email when available,
/// deterministic initials-disc fallback on any network/load error.
///
/// Cached at the framework level (Image.network keeps an in-memory cache),
/// so the same avatar rendered many times in a list re-uses one download.
class AuthorAvatar extends StatelessWidget {
  final String name;
  final String email;
  final double size;

  const AuthorAvatar({
    super.key,
    required this.name,
    required this.email,
    this.size = 18,
  });

  @override
  Widget build(BuildContext context) {
    final hash = _gravatarHash(email);
    // s=2x for HiDPI sharpness; d=404 so we can detect "no avatar" and
    // fall through to our local identicon instead of Gravatar's grey.
    final px = (size * 2).round();
    final url = 'https://www.gravatar.com/avatar/$hash?s=$px&d=404';

    return _Fallback(
      name: name,
      email: email,
      size: size,
      child: ClipOval(
        child: Image.network(
          url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, e, s) =>
              _initials(context, name, email, size),
          loadingBuilder: (ctx, child, progress) {
            if (progress == null) return child;
            return _initials(ctx, name, email, size);
          },
        ),
      ),
    );
  }
}

/// Always renders the initials disc; the network image stacks on top
/// when it loads so there is no empty flash.
class _Fallback extends StatelessWidget {
  final String name;
  final String email;
  final double size;
  final Widget child;

  const _Fallback({
    required this.name,
    required this.email,
    required this.size,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Positioned.fill(child: _initials(context, name, email, size)),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

String _gravatarHash(String email) {
  final normalised = email.trim().toLowerCase();
  return md5.convert(utf8.encode(normalised)).toString();
}

/// Identicon-style coloured disc with one or two initials. The hue is a
/// deterministic function of the email so the same author always gets the
/// same colour across the app.
Widget _initials(
    BuildContext context, String name, String email, double size) {
  final bg = _colorForEmail(email);
  final fg = _readableForeground(bg);
  final initials = _initialsFor(name, email);
  return Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
    child: Text(
      initials,
      style: TextStyle(
        color: fg,
        fontSize: size * 0.42,
        fontWeight: FontWeight.w700,
        height: 1,
      ),
    ),
  );
}

String _initialsFor(String name, String email) {
  final cleaned = name.trim();
  if (cleaned.isNotEmpty) {
    final parts = cleaned.split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return (parts.first.characters.firstOrNull ?? '').toUpperCase() +
          (parts.last.characters.firstOrNull ?? '').toUpperCase();
    }
    return (cleaned.characters.firstOrNull ?? '?').toUpperCase();
  }
  final at = email.indexOf('@');
  final local = at >= 0 ? email.substring(0, at) : email;
  return (local.characters.firstOrNull ?? '?').toUpperCase();
}

Color _colorForEmail(String email) {
  // Deterministic hue from the email — the avatar's identity colour
  // should never drift between sessions.
  final bytes = utf8.encode(email.trim().toLowerCase());
  var h = 0;
  for (final b in bytes) {
    h = (h * 31 + b) & 0x7fffffff;
  }
  final hue = (h % 360).toDouble();
  return HSLColor.fromAHSL(1, hue, 0.55, 0.45).toColor();
}

Color _readableForeground(Color bg) {
  // Standard luminance check — light text on dark backgrounds and vice
  // versa.
  return bg.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;
}
