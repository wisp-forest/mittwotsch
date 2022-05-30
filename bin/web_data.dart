import 'dart:convert';
import 'dart:io';

import 'mittwotsch.dart';

final Map<String, FaqEntry> faqMappings = {};
final List<String> docEntries = [];

void loadWebData() {
  final faqMappingsFile = openConfig("faq_mappings");
  faqMappings
      .addAll(_loadJson(faqMappingsFile).map((key, value) => MapEntry(key, FaqEntry(value["title"], value["url"]))));

  final docEntriesFile = openConfig("docs_entries");
  docEntries.addAll((_loadJson(docEntriesFile)["entries"] as List<dynamic>).cast<String>());
}

Map<String, dynamic> _loadJson(File file) {
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

class FaqEntry {
  String title, url;
  FaqEntry(this.title, this.url);
}
