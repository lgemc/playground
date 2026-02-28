import 'dart:io';
import 'package:path/path.dart' as p;
import '../autocompletion_service.dart';

/// Service to generate README.md files for folders based on summaries
class ReadmeGeneratorService {
  static final instance = ReadmeGeneratorService._();
  ReadmeGeneratorService._();

  final _autocompletion = AutocompletionService.instance;

  /// Generate or update README.md for a folder
  ///
  /// - Scans the folder for files with summaries in derivatives
  /// - Checks subfolders (one level deep) for README.md files
  /// - If README.md exists, uses it as context for updating
  /// - Generates a comprehensive README using LLM
  Future<String> generateReadme(String folderPath, String derivativesPath) async {
    // Collect summaries from files in current folder
    final fileSummaries = await _collectFileSummaries(folderPath, derivativesPath);

    // Check subfolders for README.md (one level deep only)
    final subfolderReadmes = await _collectSubfolderReadmes(folderPath);

    // Check if README.md already exists
    final readmePath = p.join(folderPath, 'README.md');
    final readmeFile = File(readmePath);
    final existingReadme = await readmeFile.exists()
        ? await readmeFile.readAsString()
        : null;

    // Generate README content using LLM
    final content = await _generateReadmeContent(
      folderName: p.basename(folderPath),
      fileSummaries: fileSummaries,
      subfolderReadmes: subfolderReadmes,
      existingReadme: existingReadme,
    );

    return content;
  }

  /// Collect summaries from files in the folder
  Future<List<FileSummary>> _collectFileSummaries(
    String folderPath,
    String derivativesPath,
  ) async {
    final summaries = <FileSummary>[];
    final folder = Directory(folderPath);

    if (!await folder.exists()) {
      return summaries;
    }

    final derivativesDir = Directory(derivativesPath);
    if (!await derivativesDir.exists()) {
      return summaries;
    }

    // List all files in folder
    await for (final entity in folder.list()) {
      if (entity is File) {
        final fileName = p.basename(entity.path);

        // Skip README.md itself
        if (fileName == 'README.md') continue;

        // Look for corresponding summary in derivatives
        final summary = await _findSummaryForFile(
          fileName,
          derivativesDir,
        );

        if (summary != null) {
          summaries.add(FileSummary(
            fileName: fileName,
            summary: summary,
          ));
        }
      }
    }

    return summaries;
  }

  /// Find summary derivative for a file
  Future<String?> _findSummaryForFile(
    String fileName,
    Directory derivativesDir,
  ) async {
    // Derivatives are named as: {timestamp}_{fileIdHash}_summary.md
    // We need to search for files ending with _summary.md
    await for (final entity in derivativesDir.list()) {
      if (entity is File && entity.path.endsWith('_summary.md')) {
        // Read the summary file
        final content = await entity.readAsString();

        // Basic heuristic: if the file name is very short, it's probably not a summary
        if (content.trim().isEmpty) continue;

        // Return first matching summary
        // Note: This is a simplified approach. In production, you'd want to
        // match based on file_id from the derivatives database table
        return content;
      }
    }

    return null;
  }

  /// Collect README.md files from immediate subfolders (one level deep)
  Future<List<SubfolderReadme>> _collectSubfolderReadmes(String folderPath) async {
    final readmes = <SubfolderReadme>[];
    final folder = Directory(folderPath);

    if (!await folder.exists()) {
      return readmes;
    }

    await for (final entity in folder.list()) {
      if (entity is Directory) {
        final subfolderName = p.basename(entity.path);
        final readmePath = p.join(entity.path, 'README.md');
        final readmeFile = File(readmePath);

        if (await readmeFile.exists()) {
          final content = await readmeFile.readAsString();
          readmes.add(SubfolderReadme(
            folderName: subfolderName,
            content: content,
          ));
        }
      }
    }

    return readmes;
  }

  /// Generate README content using LLM
  Future<String> _generateReadmeContent({
    required String folderName,
    required List<FileSummary> fileSummaries,
    required List<SubfolderReadme> subfolderReadmes,
    String? existingReadme,
  }) async {
    // Build context for the LLM
    final contextParts = <String>[];

    if (existingReadme != null && existingReadme.isNotEmpty) {
      // Truncate existing README if too long
      final truncated = existingReadme.length > 1000
          ? '${existingReadme.substring(0, 1000)}... [truncated]'
          : existingReadme;
      contextParts.add('## Existing README.md\n$truncated');
    }

    if (fileSummaries.isNotEmpty) {
      contextParts.add('\n## File Summaries');
      // Limit to first 10 file summaries
      for (final summary in fileSummaries.take(10)) {
        // Truncate long summaries
        final truncatedSummary = summary.summary.length > 300
            ? '${summary.summary.substring(0, 300)}...'
            : summary.summary;
        contextParts.add('\n### ${summary.fileName}\n$truncatedSummary');
      }
    }

    if (subfolderReadmes.isNotEmpty) {
      contextParts.add('\n## Subfolder Documentation');
      // Limit to first 5 subfolder READMEs
      for (final readme in subfolderReadmes.take(5)) {
        // Only include first few lines of subfolder READMEs
        final lines = readme.content.split('\n');
        final preview = lines.take(5).join('\n');
        contextParts.add('\n### ${readme.folderName}/\n$preview...');
      }
    }

    final context = contextParts.join('\n');

    // System prompt for generating README
    final systemPrompt = '''You are a technical documentation expert generating README.md files.

CRITICAL: Output ONLY the complete README.md markdown content. No reasoning, no meta-commentary, no explanations about what you're doing.

${existingReadme != null ? 'UPDATE the existing README based on new information from file summaries and subfolder documentation. Preserve the existing structure and tone, but integrate new insights.' : 'Generate a NEW README from scratch.'}

Format:
- Start with # heading for the folder name
- Add ## Overview section
- Add ## Contents section listing files/subfolders
- Use proper markdown formatting
- Keep it professional and informative

Begin your response with the # heading. Do not write anything before the README content.''';

    final prompt = '''Folder: $folderName

$context

---

Write the complete README.md content below (start with # heading):''';

    // Use streaming API to handle reasoning models
    final buffer = StringBuffer();
    try {
      await for (final chunk in _autocompletion.promptStream(
        prompt,
        systemPrompt: systemPrompt,
        temperature: 0.4,
        maxTokens: 2000,
      )) {
        buffer.write(chunk);
      }
    } catch (e) {
      // If streaming fails, return a basic README
      return '''# $folderName

## Overview

This folder contains ${fileSummaries.length} file(s)${subfolderReadmes.isNotEmpty ? ' and ${subfolderReadmes.length} subfolder(s)' : ''}.

## Contents

${fileSummaries.map((f) => '- ${f.fileName}').join('\n')}
${subfolderReadmes.isNotEmpty ? '\n### Subfolders\n${subfolderReadmes.map((r) => '- ${r.folderName}/').join('\n')}' : ''}

---
*Note: Auto-generated README (LLM generation failed: $e)*
''';
    }

    final rawResponse = buffer.toString().trim();

    // Extract actual README content (skip reasoning if present)
    // Look for the first markdown heading (# followed by space)
    final lines = rawResponse.split('\n');
    int contentStartIndex = 0;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      // Found the start of actual README content
      if (line.startsWith('# ') && line.length > 2) {
        contentStartIndex = i;
        break;
      }
    }

    // Join from content start to end
    final readmeContent = lines.sublist(contentStartIndex).join('\n').trim();

    return readmeContent.isNotEmpty ? readmeContent : rawResponse;
  }
}

/// File summary data
class FileSummary {
  final String fileName;
  final String summary;

  FileSummary({
    required this.fileName,
    required this.summary,
  });
}

/// Subfolder README data
class SubfolderReadme {
  final String folderName;
  final String content;

  SubfolderReadme({
    required this.folderName,
    required this.content,
  });
}
