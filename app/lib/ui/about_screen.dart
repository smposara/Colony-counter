import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_info.dart';
import '../l10n/l10n.dart';
import 'insets.dart';

/// Version, developer, contact, licence and the open-source notices.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  Future<void> _open(BuildContext context, Uri uri, String label) async {
    final messenger = ScaffoldMessenger.of(context);
    var ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
    if (!ok) {
      messenger.showSnackBar(
        SnackBar(content: Text(tr.aboutCannotOpen(label))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    Widget link(IconData icon, String title, String value, Uri uri) => ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(value),
      trailing: const Icon(Icons.open_in_new, size: 18),
      onTap: () => _open(context, uri, value),
    );
    Widget note(IconData icon, String title, String text) =>
        ListTile(leading: Icon(icon), title: Text(title), subtitle: Text(text));
    return Scaffold(
      appBar: AppBar(title: Text(tr.aboutTitle)),
      body: ListView(
        padding: scrollPadding(context, const EdgeInsets.only(bottom: 24)),
        children: [
          const SizedBox(height: 16),
          Center(
            child: Image.asset(
              'assets/icon/icon-256.png',
              width: 88,
              height: 88,
              semanticLabel: tr.appTitle,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            tr.appTitle,
            style: t.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            tr.aboutVersion(kAppVersion, kAppBuild),
            style: t.bodyMedium,
            textAlign: TextAlign.center,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 8, 32, 8),
            child: Text(
              tr.aboutTagline,
              style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(tr.aboutDeveloper),
            subtitle: const Text(kDeveloper),
          ),
          link(
            Icons.mail_outline,
            tr.aboutEmail,
            kEmail,
            Uri(
              scheme: 'mailto',
              path: kEmail,
              query: 'subject=Colony Counter $kAppVersion',
            ),
          ),
          link(Icons.language, tr.aboutWebsite, kWebsite, Uri.parse(kWebsite)),
          link(Icons.code, tr.aboutSource, kSourceUrl, Uri.parse(kSourceUrl)),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.gavel_outlined),
            title: Text('${tr.aboutLicense}: $kLicenseName'),
            subtitle: Text(tr.aboutLicenseText),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _open(context, Uri.parse(kLicenseUrl), kLicenseName),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(tr.aboutOpenSource),
            subtitle: Text(tr.aboutOpenSourceSub),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showLicensePage(
              context: context,
              applicationName: tr.appTitle,
              applicationVersion: '$kAppVersion ($kAppBuild)',
              applicationLegalese:
                  '© $kCopyrightYear $kDeveloper\n$kLicenseName · $kSourceUrl',
            ),
          ),
          const Divider(),
          note(Icons.lock_outline, tr.aboutPrivacy, tr.aboutPrivacyText),
          note(
            Icons.science_outlined,
            tr.aboutIntendedUse,
            tr.aboutIntendedUseText,
          ),
          const SizedBox(height: 16),
          Text(
            tr.aboutCopyright(kCopyrightYear, kDeveloper),
            style: t.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
