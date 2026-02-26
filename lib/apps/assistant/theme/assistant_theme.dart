import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

/// Central theme configuration for the Assistant app
class AssistantTheme {
  // Primary colors
  static const Color primary = Colors.blue;
  static const Color primaryDark = Color(0xFF1976D2);
  static const Color primaryLight = Color(0xFF42A5F5);

  // Text colors
  static const Color textPrimary = Colors.black87;
  static const Color textSecondary = Colors.black54;
  static const Color textHint = Color(0xFF9E9E9E);
  static const Color textOnPrimary = Colors.white;

  // Background colors
  static const Color background = Colors.white;
  static const Color surface = Colors.white;

  // Message bubble colors
  static const Color userBubble = Colors.blue;
  static const Color aiBubble = Color(0xFFE0E0E0);
  static const Color userBubbleText = Colors.white;
  static const Color aiBubbleText = Colors.black87;

  // Message bubble code block colors
  static const Color userCodeBackground = Color(0xFF1565C0);
  static const Color aiCodeBackground = Color(0xFFBDBDBD);
  static const Color userCodeBlockBackground = Color(0xFF0D47A1);
  static const Color aiCodeBlockBackground = Color(0xFFBDBDBD);

  // Input field colors
  static const Color inputBorder = Color(0xFFE0E0E0);
  static const Color inputBorderFocused = Colors.blue;
  static const Color inputText = Colors.black87;
  static const Color inputHint = Color(0xFF757575);

  // AppBar
  static const Color appBarBackground = Colors.blue;
  static const Color appBarForeground = Colors.white;

  // Shadows
  static BoxShadow inputShadow = BoxShadow(
    color: Colors.grey.withValues(alpha: 0.2),
    spreadRadius: 1,
    blurRadius: 5,
    offset: const Offset(0, -3),
  );

  // Markdown styles for user messages (blue bubble)
  static MarkdownStyleSheet userMarkdownStyle = MarkdownStyleSheet(
    p: const TextStyle(color: userBubbleText, fontSize: 15),
    h1: const TextStyle(
        color: userBubbleText, fontSize: 24, fontWeight: FontWeight.bold),
    h2: const TextStyle(
        color: userBubbleText, fontSize: 20, fontWeight: FontWeight.bold),
    h3: const TextStyle(
        color: userBubbleText, fontSize: 18, fontWeight: FontWeight.bold),
    code: const TextStyle(
      color: userBubbleText,
      backgroundColor: userCodeBackground,
      fontFamily: 'monospace',
    ),
    codeblockDecoration: BoxDecoration(
      color: userCodeBlockBackground,
      borderRadius: BorderRadius.circular(8),
    ),
    blockquote: TextStyle(
        color: userBubbleText.withValues(alpha: userBubbleText.a * 0.8),
        fontStyle: FontStyle.italic),
    listBullet: const TextStyle(color: userBubbleText),
    a: const TextStyle(
        color: userBubbleText, decoration: TextDecoration.underline),
    tableHead: const TextStyle(
        color: userBubbleText, fontSize: 15, fontWeight: FontWeight.bold),
    tableBody: const TextStyle(color: userBubbleText, fontSize: 15),
    tableBorder: const TableBorder(
      top: BorderSide(color: Color(0xB3FFFFFF)),
      bottom: BorderSide(color: Color(0xB3FFFFFF)),
      left: BorderSide(color: Color(0xB3FFFFFF)),
      right: BorderSide(color: Color(0xB3FFFFFF)),
      horizontalInside: BorderSide(color: Color(0xB3FFFFFF)),
      verticalInside: BorderSide(color: Color(0xB3FFFFFF)),
    ),
    tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
  );

  // Markdown styles for AI messages (gray bubble)
  static MarkdownStyleSheet aiMarkdownStyle = MarkdownStyleSheet(
    p: const TextStyle(color: aiBubbleText, fontSize: 15),
    h1: const TextStyle(
        color: aiBubbleText, fontSize: 24, fontWeight: FontWeight.bold),
    h2: const TextStyle(
        color: aiBubbleText, fontSize: 20, fontWeight: FontWeight.bold),
    h3: const TextStyle(
        color: aiBubbleText, fontSize: 18, fontWeight: FontWeight.bold),
    code: const TextStyle(
      color: aiBubbleText,
      backgroundColor: aiCodeBackground,
      fontFamily: 'monospace',
    ),
    codeblockDecoration: BoxDecoration(
      color: aiCodeBlockBackground,
      borderRadius: BorderRadius.circular(8),
    ),
    blockquote: TextStyle(
        color: aiBubbleText.withValues(alpha: aiBubbleText.a * 0.8),
        fontStyle: FontStyle.italic),
    listBullet: const TextStyle(color: aiBubbleText),
    a: const TextStyle(
        color: Colors.blue, decoration: TextDecoration.underline),
    tableHead: const TextStyle(
        color: aiBubbleText, fontSize: 15, fontWeight: FontWeight.bold),
    tableBody: const TextStyle(color: aiBubbleText, fontSize: 15),
    tableBorder: const TableBorder(
      top: BorderSide(color: Color(0x80000000)),
      bottom: BorderSide(color: Color(0x80000000)),
      left: BorderSide(color: Color(0x80000000)),
      right: BorderSide(color: Color(0x80000000)),
      horizontalInside: BorderSide(color: Color(0x80000000)),
      verticalInside: BorderSide(color: Color(0x80000000)),
    ),
    tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
  );

  // Input decoration
  static InputDecoration getInputDecoration({
    required String hintText,
    bool enabled = true,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(color: inputHint),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: const BorderSide(color: inputBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: const BorderSide(color: inputBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: const BorderSide(color: inputBorderFocused, width: 2),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 20,
        vertical: 10,
      ),
    );
  }
}
