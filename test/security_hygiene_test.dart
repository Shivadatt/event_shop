import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Nothing in this repo may carry a live credential, and the SEO shell may only carry a token that
/// is obviously a token. `web/index.html` points at this file when it says so; if you change what is
/// scanned, change that comment too.
///
/// Deliberately narrow: it proves what is COMMITTED is clean. It does not prove the deployed bundle
/// is correct, and it cannot — `{{SITE_ORIGIN}}` is meant to survive into source and must not
/// survive into `build/web`. Substituting it is a deploy-time step (docs/backend-setup.md), and a
/// test that failed on an unsubstituted local build would only teach everyone to ignore red tests.

/// Directories that are generated, vendored, or binary — scanning them produces noise, not signal.
const _skippedDirs = <String>{
  '.git', '.dart_tool', 'build', '.idea', 'node_modules', 'coverage',
  '.qoder', 'macos', 'linux', 'windows', 'ios', 'android',
};

/// Shapes a real credential takes. Matched structurally, so a placeholder that merely says "key" is
/// not flagged while an actual live-format secret cannot slip through.
const _credentialPatterns = <String, Pattern>{
  'firebase-service-account-private-key': 'BEGIN RSA PRIVATE KEY',
  'generic-private-key': 'BEGIN PRIVATE KEY',
  'supabase-service-role-jwt': 'eyJhbGciOiJIUzI1NiJ9',
  'stripe-live-secret': r'sk_live_',
  'razorpay-live-secret': r'rzp_live_',
  'google-api-key': r'AIza[0-9A-Za-z_\-]{35}',
  'aws-access-key-id': r'AKIA[0-9A-Z]{16}',
  'firebase-adminsdk-service-account': 'firebase_admin_sdk',
  'pem-certificate': '-----BEGIN CERTIFICATE-----',
};

/// Placeholder values that look like credentials but are, by wording, unmistakably not.
const _allowedPlaceholders = <String>{
  'localhost-emulator-not-a-real-key',
  'emulator-demo',
  'AIzaSyDUMMY000000000000000000000000REPLACEME',
};

/// The only three files allowed to hold the deploy token.
const _tokenAllowedFiles = <String>{
  'web/index.html',
  'web/robots.txt',
  'web/sitemap.xml',
};

/// Files that may name the token without shipping it: the SEO helpers that define and guard it,
/// the tests that assert the substitution, and the docs that explain the deploy step.
const _tokenAllowedPrefixes = <String>{'lib/app/seo/', 'test/', 'docs/'};

/// Repo-relative path for a filesystem entry.
///
/// `Directory.current.listSync` returns paths rooted at the package directory — on Windows that is
/// `D:/event_shop/...` — while every allow-list below is written in repo-relative paths. Comparing
/// without stripping the root silently disables those exemptions and turns the scan's own source
/// into an offender.
String _relativeToRepo(String path) {
  final normalised = path.replaceAll('\\', '/');
  final root = '${Directory.current.path.replaceAll('\\', '/')}/';
  if (normalised.startsWith(root)) return normalised.substring(root.length);
  return normalised.replaceFirst('./', '');
}

Iterable<File> _trackedTextFiles() {
  final out = <File>[];
  for (final entity in Directory.current.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final relative = _relativeToRepo(entity.path);
    final parts = relative.split('/');
    if (parts.any((p) => _skippedDirs.contains(p))) continue;
    // Only scan source we would actually ship or deploy; lock files and wiki dumps are their own
    // universe of strings and are covered by the pubspec/npm review that generates them.
    const allowedExtensions = <String>{
      '.dart', '.js', '.mjs', '.json', '.html', '.css', '.yaml', '.yml',
      '.md', '.txt', '.rules', '.sh', '.ps1', '.bat',
    };
    if (!allowedExtensions.any(relative.endsWith)) continue;
    if (relative.endsWith('.lock')) continue;
    out.add(entity);
  }
  return out;
}

void main() {
  group('security hygiene', () {
    test('no committed file contains a credential-shaped string', () {
      final offenders = <String>[];
      for (final file in _trackedTextFiles()) {
        final relative = _relativeToRepo(file.path);
        // This file's own pattern table quotes the shapes it hunts, so scanning it would flag
        // nine "leaks" that are the detector's source. Nothing else is exempt.
        if (relative == 'test/security_hygiene_test.dart') continue;
        String body;
        try {
          body = file.readAsStringSync();
        } on Object {
          continue; // Undecodable (binary masquerading as text) — not this test's problem.
        }
        for (final entry in _credentialPatterns.entries) {
          if (!body.contains(entry.value)) continue;
          offenders.add('$relative: ${entry.key}');
        }
        // A service-role key handed to a client build is the single most damaging mistake available
        // in this stack; catch any mention of the variable even without a JWT prefix.
        if (relative.startsWith('lib/') &&
            RegExp(r'SUPABASE_SERVICE_ROLE_KEY\s*[:=]\s*[\x27"][A-Za-z0-9_\-]{20,}')
                .hasMatch(body)) {
          offenders.add('$relative: service-role key assigned as a literal in client code');
        }
      }
      expect(offenders, isEmpty, reason: 'Committing a real credential is unrecoverable — rotate it '
          'in the provider, then remove it from history.');
    }, onPlatform: {'browser': const Skip('filesystem scan is not available on the web test runner')});

    test('the deploy origin token appears only in the SEO shell files', () {
      final offenders = <String>[];
      for (final file in _trackedTextFiles()) {
        final relative = _relativeToRepo(file.path);
        if (_tokenAllowedFiles.contains(relative) ||
            _tokenAllowedPrefixes.any(relative.startsWith)) {
          continue;
        }
        if (file.readAsStringSync().contains('{{SITE_ORIGIN}}')) {
          offenders.add(relative);
        }
      }
      expect(offenders, isEmpty,
          reason: 'A token in a served artefact outside web/ would ship as literal {{SITE_ORIGIN}} '
              'text, because the substitution step only rewrites the shell files.');
    }, onPlatform: {'browser': const Skip('filesystem scan is not available on the web test runner')});

    test('no real project id is committed in firebase config', () {
      // firebase.json ships a templated id on purpose; .firebaserc is too — `firebase use` rewrites
      // it locally. What must never be committed is a real project id inside it.
      final rc = File('.firebaserc');
      if (rc.existsSync()) {
        final projects =
            (jsonDecode(rc.readAsStringSync()) as Map<String, dynamic>)['projects'];
        if (projects is Map) {
          for (final entry in projects.entries) {
            final id = entry.value.toString();
            expect(
              id,
              matches(r'^(demo-[a-z0-9_-]+|REPLACE_WITH_YOUR_FIREBASE_PROJECT_ID)$'),
              reason: '.firebaserc pins ${entry.key}="$id" for whoever clones this repo. A live '
                  'project id belongs in your local `firebase use`, not in source '
                  '(docs/backend-setup.md).',
            );
          }
        }
      }

      final json = File('firebase.json').readAsStringSync();
      expect(json, isNot(contains('storageBucket')));
      expect(json, contains('"rules": "firestore.rules"'),
          reason: 'The deploy config must point at the strict rules, not at the permissive local one.');
      expect(File('firebase.local.json').readAsStringSync(), isNot(contains('"rules"')),
          reason: 'The local demo config must stay rules-less so it can never be mistaken for the '
              'deploy target.');
    }, onPlatform: {'browser': const Skip('filesystem scan is not available on the web test runner')});

    test('placeholder credentials are unmistakably placeholders', () {
      for (final placeholder in _allowedPlaceholders) {
        expect(placeholder, isNot(matches(RegExp(r'^AIza[0-9A-Za-z_\-]{35}$'))),
            reason: '$placeholder is meant to be inert; if it ever matches a real key shape, '
                'substitute-and-scan stops meaning anything.');
      }
      expect(
        File('lib/app/core/env.dart').readAsStringSync(),
        contains('localhost-emulator-not-a-real-key'),
        reason: 'Emulator mode depends on this wording to stay visibly fake.',
      );
    }, onPlatform: {'browser': const Skip('filesystem scan is not available on the web test runner')});
  });
}
