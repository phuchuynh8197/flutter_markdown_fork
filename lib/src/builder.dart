// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/services.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/github.dart';
import '_functions_io.dart' if (dart.library.js_interop) '_functions_web.dart';
import 'style_sheet.dart';
import 'widget.dart';

final List<String> _kBlockTags = <String>[
  'p',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'li',
  'blockquote',
  'pre',
  'ol',
  'ul',
  'hr',
  'table',
  'thead',
  'tbody',
  'tr',
  'section',
];

const List<String> _kListTags = <String>['ul', 'ol'];

bool _isBlockTag(String? tag) => _kBlockTags.contains(tag);

bool _isListTag(String tag) => _kListTags.contains(tag);

class _BlockElement {
  _BlockElement(this.tag);

  final String? tag;
  final List<Widget> children = <Widget>[];

  int nextListIndex = 0;
}

class _TableElement {
  final List<TableRow> rows = <TableRow>[];
}

/// Holds configuration data for an image in a Markdown document.
class MarkdownImageConfig {
  /// Creates a new [MarkdownImageConfig] instance.
  MarkdownImageConfig({
    required this.uri,
    this.title,
    this.alt,
    this.width,
    this.height,
  });

  /// The URI of the image.
  final Uri uri;

  /// The title of the image, displayed on hover.
  final String? title;

  /// The alternative text for the image, displayed if the image cannot be loaded.
  final String? alt;

  /// The desired width of the image.
  final double? width;

  /// The desired height of the image.
  final double? height;
}

/// A collection of widgets that should be placed adjacent to (inline with)
/// other inline elements in the same parent block.
///
/// Inline elements can be textual (a/em/strong) represented by [Text.rich]
/// widgets or images (img) represented by [Image.network] widgets.
///
/// Inline elements can be nested within other inline elements, inheriting their
/// parent's style along with the style of the block they are in.
///
/// When laying out inline widgets, first, any adjacent Text.rich widgets are
/// merged, then, all inline widgets are enclosed in a parent [Wrap] widget.
class _InlineElement {
  _InlineElement(this.tag, {this.style});

  final String? tag;

  /// Created by merging the style defined for this element's [tag] in the
  /// delegate's [MarkdownStyleSheet] with the style of its parent.
  final TextStyle? style;

  final List<Widget> children = <Widget>[];
}

/// A delegate used by [MarkdownBuilder] to control the widgets it creates.
abstract class MarkdownBuilderDelegate {
  /// Returns the [BuildContext] of the [MarkdownWidget].
  ///
  /// The context will be passed down to the
  /// [MarkdownElementBuilder.visitElementBefore] method and allows elements to
  /// get information from the context.
  BuildContext get context;

  /// Returns a gesture recognizer to use for an `a` element with the given
  /// text, `href` attribute, and title.
  GestureRecognizer createLink(String text, String? href, String title);

  /// Returns formatted text to use to display the given contents of a `pre`
  /// element.
  ///
  /// The `styleSheet` is the value of [MarkdownBuilder.styleSheet].
  TextSpan formatText(MarkdownStyleSheet styleSheet, String code);
}

/// Builds a [Widget] tree from parsed Markdown.
///
/// See also:
///
///  * [Markdown], which is a widget that parses and displays Markdown.
class MarkdownBuilder implements md.NodeVisitor {
  /// Creates an object that builds a [Widget] tree from parsed Markdown.
  MarkdownBuilder({
    required this.delegate,
    required this.selectable,
    required this.styleSheet,
    required this.imageDirectory,
    @Deprecated('Use sizedImageBuilder instead') this.imageBuilder,
    required this.sizedImageBuilder,
    required this.checkboxBuilder,
    required this.bulletBuilder,
    required this.builders,
    required this.paddingBuilders,
    required this.listItemCrossAxisAlignment,
    this.fitContent = false,
    this.onSelectionChanged,
    this.onTapText,
    this.softLineBreak = false,
  }) : assert(imageBuilder == null || sizedImageBuilder == null,
  'Only one of imageBuilder or sizedImageBuilder may be specified.');

  /// A delegate that controls how link and `pre` elements behave.
  final MarkdownBuilderDelegate delegate;

  /// If true, the text is selectable.
  ///
  /// Defaults to false.
  final bool selectable;

  /// Defines which [TextStyle] objects to use for each type of element.
  final MarkdownStyleSheet styleSheet;

  /// The base directory holding images referenced by Img tags with local or network file paths.
  final String? imageDirectory;

  /// {@template flutter_markdown.builder.MarkdownBuilder.imageBuilder}
  /// Called to build an image widget.
  ///
  /// This builder allows for custom rendering of images within the Markdown content.
  /// It provides the image `Uri`, `title`, and `alt` text.
  ///
  /// **Deprecated:** Use [sizedImageBuilder] instead, which offers more comprehensive
  /// image information.
  ///
  /// Only one of [imageBuilder] or [sizedImageBuilder] may be specified.
  ///
  /// {@endtemplate}
  @Deprecated('Use sizedImageBuilder instead')
  final MarkdownImageBuilder? imageBuilder;

  /// {@template flutter_markdown.builder.MarkdownBuilder.sizedImageBuilder}
  /// Called to build an image widget with size information.
  ///
  /// This builder allows for custom rendering of images within the Markdown content
  /// when size information is available. It provides a [MarkdownImageConfig]
  /// containing the `Uri`, `title`, `alt`, `width`, and `height` of the image.
  ///
  /// If both [imageBuilder] and [sizedImageBuilder] are `null`, a default image builder
  /// will be used.
  /// when size information is available. It provides a [MarkdownImageConfig]
  /// containing the `Uri`, `title`, `alt`, `width`, and `height` of the image.
  ///
  /// If both [imageBuilder] and [sizedImageBuilder] are `null`, a default
  /// image builder will be used.
  ///
  /// Only one of [imageBuilder] or [sizedImageBuilder] may be specified.
  ///
  /// {@endtemplate}
  final MarkdownSizedImageBuilder? sizedImageBuilder;

  /// Call when build a checkbox widget.
  final MarkdownCheckboxBuilder? checkboxBuilder;

  /// Called when building a custom bullet.
  final MarkdownBulletBuilder? bulletBuilder;

  /// Call when build a custom widget.
  final Map<String, MarkdownElementBuilder> builders;

  /// Call when build a padding for widget.
  final Map<String, MarkdownPaddingBuilder> paddingBuilders;

  /// Whether to allow the widget to fit the child content.
  final bool fitContent;

  /// Controls the cross axis alignment for the bullet and list item content
  /// in lists.
  ///
  /// Defaults to [MarkdownListItemCrossAxisAlignment.baseline], which
  /// does not allow for intrinsic height measurements.
  final MarkdownListItemCrossAxisAlignment listItemCrossAxisAlignment;

  /// Called when the user changes selection when [selectable] is set to true.
  final MarkdownOnSelectionChangedCallback? onSelectionChanged;

  /// Default tap handler used when [selectable] is set to true
  final VoidCallback? onTapText;

  /// The soft line break is used to identify the spaces at the end of aline of
  /// text and the leading spaces in the immediately following the line of text.
  ///
  /// Default these spaces are removed in accordance with the Markdown
  /// specification on soft line breaks when lines of text are joined.
  final bool softLineBreak;

  final List<String> _listIndents = <String>[];
  final List<_BlockElement> _blocks = <_BlockElement>[];
  final List<_TableElement> _tables = <_TableElement>[];
  final List<_InlineElement> _inlines = <_InlineElement>[];
  final List<GestureRecognizer> _linkHandlers = <GestureRecognizer>[];
  String? _currentBlockTag;
  String? _lastVisitedTag;
  bool _isInBlockquote = false;

  /// Returns widgets that display the given Markdown nodes.
  ///
  /// The returned widgets are typically used as children in a [ListView].
  List<Widget> build(List<md.Node> nodes) {
    _listIndents.clear();
    _blocks.clear();
    _tables.clear();
    _inlines.clear();
    _linkHandlers.clear();
    _isInBlockquote = false;

    builders.forEach((String key, MarkdownElementBuilder value) {
      if (value.isBlockElement()) {
        _kBlockTags.add(key);
      }
    });

    _blocks.add(_BlockElement(null));

    for (final md.Node node in nodes) {
      assert(_blocks.length == 1);
      node.accept(this);
    }

    assert(_tables.isEmpty);
    assert(_inlines.isEmpty);
    assert(!_isInBlockquote);
    return _blocks.single.children;
  }

  @override
  bool visitElementBefore(md.Element element) {
    final String tag = element.tag;
    _currentBlockTag ??= tag;
    _lastVisitedTag = tag;

    if (builders.containsKey(tag)) {
      builders[tag]!.visitElementBefore(element);
    }

    if (paddingBuilders.containsKey(tag)) {
      paddingBuilders[tag]!.visitElementBefore(element);
    }

    int? start;
    if (_isBlockTag(tag)) {
      _addAnonymousBlockIfNeeded();
      if (_isListTag(tag)) {
        _listIndents.add(tag);
        if (element.attributes['start'] != null) {
          start = int.parse(element.attributes['start']!) - 1;
        }
      } else if (tag == 'blockquote') {
        _isInBlockquote = true;
      } else if (tag == 'table') {
        _tables.add(_TableElement());
      } else if (tag == 'tr') {
        final int length = _tables.single.rows.length;
        BoxDecoration? decoration =
        styleSheet.tableCellsDecoration as BoxDecoration?;
        if (length == 0 || length.isOdd) {
          decoration = null;
        }
        _tables.single.rows.add(TableRow(
          decoration: decoration,
          // TODO(stuartmorgan): This should be fixed, not suppressed; enabling
          // this lint warning exposed that the builder is modifying the
          // children of TableRows, even though they are @immutable.
          // ignore: prefer_const_literals_to_create_immutables
          children: <Widget>[],
        ));
      }
      final _BlockElement bElement = _BlockElement(tag);
      if (start != null) {
        bElement.nextListIndex = start;
      }
      _blocks.add(bElement);
    } else {
      if (tag == 'a') {
        final String? text = extractTextFromElement(element);
        // Don't add empty links
        if (text == null) {
          return false;
        }
        final String? destination = element.attributes['href'];
        final String title = element.attributes['title'] ?? '';

        _linkHandlers.add(
          delegate.createLink(text, destination, title),
        );
      }

      _addParentInlineIfNeeded(_blocks.last.tag);

      // The Markdown parser passes empty table data tags for blank
      // table cells. Insert a text node with an empty string in this
      // case for the table cell to get properly created.
      if (element.tag == 'td' &&
          element.children != null &&
          element.children!.isEmpty) {
        element.children!.add(md.Text(''));
      }

      final TextStyle parentStyle = _inlines.last.style!;
      _inlines.add(_InlineElement(
        tag,
        style: parentStyle.merge(styleSheet.styles[tag]),
      ));
    }

    return true;
  }

  /// Returns the text, if any, from [element] and its descendants.p
  String? extractTextFromElement(md.Node element) {
    return element is md.Element && (element.children?.isNotEmpty ?? false)
        ? element.children!
        .map((md.Node e) =>
    e is md.Text ? e.text : extractTextFromElement(e))
        .join()
        : (element is md.Element && (element.attributes.isNotEmpty)
        ? element.attributes['alt']
        : '');
  }

  @override
  void visitText(md.Text text) {
    // Don't allow text directly under the root.
    if (_blocks.last.tag == null) {
      return;
    }

    _addParentInlineIfNeeded(_blocks.last.tag);

    // Define trim text function to remove spaces from text elements in
    // accordance with Markdown specifications.
    String trimText(String text) {
      // The leading spaces pattern is used to identify spaces
      // at the beginning of a line of text.
      final RegExp leadingSpacesPattern = RegExp(r'^ *');

      // The soft line break is used to identify the spaces at the end of a line
      // of text and the leading spaces in the immediately following the line
      // of text. These spaces are removed in accordance with the Markdown
      // specification on soft line breaks when lines of text are joined.
      final RegExp softLineBreakPattern = RegExp(r' ?\n *');

      // Leading spaces following a hard line break are ignored.
      // https://github.github.com/gfm/#example-657
      // Leading spaces in paragraph or list item are ignored
      // https://github.github.com/gfm/#example-192
      // https://github.github.com/gfm/#example-236
      if (const <String>['ul', 'ol', 'li', 'p', 'br']
          .contains(_lastVisitedTag)) {
        text = text.replaceAll(leadingSpacesPattern, '');
      }

      if (softLineBreak) {
        return text;
      }
      return text.replaceAll(softLineBreakPattern, ' ');
    }

    Widget? child;
    if (_blocks.isNotEmpty && builders.containsKey(_blocks.last.tag)) {
      child = builders[_blocks.last.tag!]!
          .visitText(text, styleSheet.styles[_blocks.last.tag!]);
    } else if (_blocks.last.tag == 'pre') {
      try {
        final customTheme = Map<String, TextStyle>.from(githubTheme)
          ..updateAll((key, value) {
            return value.copyWith(
              backgroundColor: Colors.transparent, // bỏ nền
              decoration: TextDecoration.none,     // bỏ gạch dưới / highlight
            );
          });

        child = _ScrollControllerBuilder(
          builder: (BuildContext context, ScrollController preScrollController,
              Widget? child) {
            return Container(
              child: RawScrollbar(
                controller: preScrollController,
                thumbVisibility: false,
                thickness: 4,
                padding: EdgeInsets.only(bottom: 0),
                radius: const Radius.circular(4),
                thumbColor: Colors.grey.shade700,
                scrollbarOrientation: ScrollbarOrientation.bottom, // 👈 nằm sát đáy
                child: SingleChildScrollView(
                  controller: preScrollController,
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.only(top: 12, bottom: 12, left: 16, right: 16),
                  child: child,
                ),
              ),
            );
          },
          child: Container(
            child: HighlightView(
              text.text,
              language: detectLanguage(text.text),
              theme: customTheme,
              padding: styleSheet.codeblockPadding,
              textStyle: (styleSheet.code ?? const TextStyle()).copyWith(
                fontFamily: 'monospace',
                backgroundColor: Colors.transparent, // ép xoá nền chung
                decoration: TextDecoration.none,
              ),
            ),
          ),
        );
      } catch (e) {
        // Fallback to simple text if highlighting fails
        child = _buildRichText(
          TextSpan(
            style: (styleSheet.code ?? const TextStyle()).copyWith(
              fontFamily: 'monospace',
              backgroundColor: Colors.transparent,
              decoration: TextDecoration.none,
            ),
            text: text.text,
          ),
        );
      }
    } else {
      final raw = text.text.trim();

      final blockMath = RegExp(r'\$\$([\s\S]+?)\$\$|\\\[([\s\S]+?)\\\]', dotAll: true);
      final inlineMath = RegExp(
        r'(\$(.+?)\$|\\\((.+?)\\\)|\\(Delta|delta|triangle|neq))',
        dotAll: true,
      );
      final squareBracketMath = RegExp(r'^\[(.+)\]$', dotAll: true);

      // Block math: $$ ... $$ hoặc \[...\]
      if (blockMath.hasMatch(raw)) {
        try {
          final match = blockMath.firstMatch(raw)!;
          final latex = (match.group(1) ?? match.group(2))!.trim();

          child = Math.tex(
            r'$' + latex + r'$',
            mathStyle: MathStyle.display,
            textStyle: const TextStyle(fontSize: 16),
            onErrorFallback: (err) {
              return Text(latex);
            },
          );
        } catch (e) {
          // Fallback to plain text if math rendering fails
          child = _buildRichText(
            TextSpan(
              style: _isInBlockquote
                  ? styleSheet.blockquote!.merge(_inlines.last.style)
                  : _inlines.last.style,
              text: raw,
              recognizer: _linkHandlers.isNotEmpty ? _linkHandlers.last : null,
            ),
            textAlign: _textAlignForBlockTag(_currentBlockTag),
          );
        }
      }
// Block math: [ ... ]
      else if (squareBracketMath.hasMatch(raw)) {
        try {
          final match = squareBracketMath.firstMatch(raw)!;
          final latex = match.group(1)!.trim();

          child = Math.tex(
            latex,
            mathStyle: MathStyle.display,
            textStyle: const TextStyle(fontSize: 16),
            onErrorFallback: (err) {
              return Text(latex);
            },
          );
        } catch (e) {
          // Fallback to plain text if math rendering fails
          child = _buildRichText(
            TextSpan(
              style: _isInBlockquote
                  ? styleSheet.blockquote!.merge(_inlines.last.style)
                  : _inlines.last.style,
              text: raw,
              recognizer: _linkHandlers.isNotEmpty ? _linkHandlers.last : null,
            ),
            textAlign: _textAlignForBlockTag(_currentBlockTag),
          );
        }
      } else if (inlineMath.hasMatch(raw)) {
        try {
          final spans = <InlineSpan>[];
          int lastIndex = 0;

          for (final match in inlineMath.allMatches(raw)) {
            if (match.start > lastIndex) {
              spans.add(TextSpan(text: raw.substring(lastIndex, match.start)));
            }

            final latex = (match.group(1) ?? match.group(2))!.trim();

            spans.add(
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Math.tex(
                  latex,
                  mathStyle: MathStyle.text,
                  textStyle: const TextStyle(fontSize: 16),
                  onErrorFallback: (err) {
                    return Text(latex);
                  },
                ),
              ),
            );
            lastIndex = match.end;
          }

          if (lastIndex < raw.length) {
            spans.add(TextSpan(text: raw.substring(lastIndex)));
          }

          child = _buildRichText(
            TextSpan(
              style: _isInBlockquote
                  ? styleSheet.blockquote!.merge(_inlines.last.style)
                  : _inlines.last.style,
              children: spans,
            ),
            textAlign: _textAlignForBlockTag(_currentBlockTag),
          );
        } catch (e) {
          // Fallback to plain text if math rendering fails
          child = _buildRichText(
            TextSpan(
              style: _isInBlockquote
                  ? styleSheet.blockquote!.merge(_inlines.last.style)
                  : _inlines.last.style,
              text: raw,
              recognizer: _linkHandlers.isNotEmpty ? _linkHandlers.last : null,
            ),
            textAlign: _textAlignForBlockTag(_currentBlockTag),
          );
        }
      } else {

        child = _buildRichText(
          TextSpan(
            style: _isInBlockquote
                ? styleSheet.blockquote!.merge(_inlines.last.style)
                : _inlines.last.style,
            text: raw,
            recognizer: _linkHandlers.isNotEmpty ? _linkHandlers.last : null,
          ),
          textAlign: _textAlignForBlockTag(_currentBlockTag),
        );
      }

    }
    if (child != null) {
      _inlines.last.children.add(child);
    }

    _lastVisitedTag = null;
  }

  String detectLanguage(String codeBlock) {
    try {
      // Regex lấy ngôn ngữ sau dấu ```
      final langRegex = RegExp(r"^```(\w+)", multiLine: true);
      final match = langRegex.firstMatch(codeBlock);

      if (match != null) {
        return match.group(1)?.toLowerCase() ?? 'plaintext';
      }

      // Fallback danh sách ngôn ngữ phổ biến
      const supportedLangs = [
        'dart', 'java', 'kotlin', 'swift',
        'c', 'cpp', 'csharp',
        'python', 'javascript', 'typescript',
        'go', 'rust', 'php', 'ruby',
        'html', 'xml', 'css', 'scss', 'less',
        'json', 'yaml', 'markdown', 'graphql',
        'sql', 'bash', 'shell', 'powershell',
        'dockerfile', 'makefile', 'ini', 'properties', 'toml', 'diff',
      ];

      // Check từ khóa xuất hiện trong code để đoán
      final lower = codeBlock.toLowerCase();

      if (lower.contains('class ') && lower.contains('public static void main')) {
        return 'java';
      }
      if (lower.contains('import dart:') || lower.contains('@override')) {
        return 'dart';
      }
      if (lower.contains('fun ') && lower.contains('val ')) {
        return 'kotlin';
      }
      if (lower.contains('func ') && lower.contains('let ')) {
        return 'swift';
      }
      if (lower.contains('#include') || lower.contains('printf(')) {
        return 'c';
      }
      if (lower.contains('cout <<') || lower.contains('std::')) {
        return 'cpp';
      }
      if (lower.contains('using System') || lower.contains('Console.WriteLine')) {
        return 'csharp';
      }
      if (lower.contains('def ') && lower.contains('print(')) {
        return 'python';
      }
      if (lower.contains('function ') || lower.contains('console.log')) {
        return 'javascript';
      }
      if (lower.contains('let ') && lower.contains(': number')) {
        return 'typescript';
      }
      if (lower.contains('package main') && lower.contains('fmt.')) {
        return 'go';
      }
      if (lower.contains('fn main()') && lower.contains('let mut')) {
        return 'rust';
      }
      if (lower.contains('<?php')) {
        return 'php';
      }
      if (lower.contains('puts ') || lower.contains('end')) {
        return 'ruby';
      }
      if (lower.contains('<html') || lower.contains('<!DOCTYPE html>')) {
        return 'html';
      }
      if (lower.contains('<') && lower.contains('/>')) {
        return 'xml';
      }
      if (lower.contains('{') && lower.contains('color:')) {
        return 'css';
      }
      if (lower.contains('\$') && lower.contains('margin')) {
        return 'scss';
      }
      if (lower.contains('@')) {
        return 'less';
      }
      if (lower.trim().startsWith('{') || lower.contains('"')) {
        return 'json';
      }
      if (lower.contains(':') && lower.contains('\n-')) {
        return 'yaml';
      }
      if (lower.contains('#') && lower.contains(' ')) {
        return 'markdown';
      }
          if (lower.contains('query') && lower.contains('{')) {
        return 'graphql';
      }
      if (lower.contains('select ') || lower.contains('insert into')) {
        return 'sql';
      }
      if (lower.startsWith('#!') || lower.contains('echo ')) {
        return 'bash';
      }
      if (lower.contains('powershell') || lower.contains('Write-Host')) {
        return 'powershell';
      }
      if (lower.contains('from ') && lower.contains('copy ')) {
        return 'dockerfile';
      }
      if (lower.contains('make:') || lower.contains('\t')) {
        return 'makefile';
      }
      if (lower.contains('=') && lower.contains('[')) {
        return 'ini';
      }
      if (lower.contains('=') && lower.contains('.')) {
        return 'properties';
      }
      if (lower.contains('=') && lower.contains('[table]')) {
        return 'toml';
      }
      if (lower.contains('---') || lower.contains('+++')) {
        return 'diff';
      }

      return 'plaintext';
    } catch (e) {
      // Fallback to plaintext if language detection fails
      return 'plaintext';
    }
  }

  @override
  void visitElementAfter(md.Element element) {
    final String tag = element.tag;

    if (_isBlockTag(tag)) {
      _addAnonymousBlockIfNeeded();

      final _BlockElement current = _blocks.removeLast();

      Widget defaultChild() {
        if (current.children.isNotEmpty) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: fitContent
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.stretch,
            children: current.children,
          );
        } else {
          return const SizedBox();
        }
      }

      Widget child = builders[tag]?.visitElementAfterWithContext(
        delegate.context,
        element,
        styleSheet.styles[tag],
        _inlines.isNotEmpty ? _inlines.last.style : null,
      ) ??
          defaultChild();

      if (_isListTag(tag)) {
        assert(_listIndents.isNotEmpty);
        _listIndents.removeLast();
      } else if (tag == 'li') {
        if (_listIndents.isNotEmpty) {
          if (element.children!.isEmpty) {
            element.children!.add(md.Text(''));
          }
          Widget bullet;
          final dynamic el = element.children![0];
          if (el is md.Element && el.attributes['type'] == 'checkbox') {
            final bool val = el.attributes.containsKey('checked');
            bullet = _buildCheckbox(val);
          } else {
            bullet = _buildBullet(_listIndents.last);
          }
          child = Row(
            mainAxisSize: fitContent ? MainAxisSize.min : MainAxisSize.max,
            textBaseline: listItemCrossAxisAlignment ==
                MarkdownListItemCrossAxisAlignment.start
                ? null
                : TextBaseline.alphabetic,
            crossAxisAlignment: listItemCrossAxisAlignment ==
                MarkdownListItemCrossAxisAlignment.start
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.baseline,
            children: <Widget>[
              SizedBox(
                width: styleSheet.listIndent! +
                    styleSheet.listBulletPadding!.left +
                    styleSheet.listBulletPadding!.right,
                child: bullet,
              ),
              Flexible(
                fit: fitContent ? FlexFit.loose : FlexFit.tight,
                child: child,
              )
            ],
          );
        }
      } else if (tag == 'table') {
        try {
          child = _ScrollControllerBuilder(
            builder: (BuildContext context, ScrollController tableScrollController,
                Widget? child) {
              return Container(
                child: RawScrollbar(
                  controller: tableScrollController,
                  thumbVisibility: false,
                  thickness: 4,
                  padding: EdgeInsets.only(bottom: 0),
                  radius: const Radius.circular(4),
                  thumbColor: Colors.grey.shade700,
                  scrollbarOrientation: ScrollbarOrientation.bottom,
                  child: SingleChildScrollView(
                    controller: tableScrollController,
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.only(top: 12, bottom: 12, left: 16, right: 16),
                    child: child,
                  ),
                ),
              );
            },
            child: _buildTable(),
          );
        } catch (e) {
          // Fallback to simple table if scrolling fails
          child = _buildTable();
        }
      } else if (tag == 'blockquote') {
        _isInBlockquote = false;
        try {
          child = DecoratedBox(
            decoration: styleSheet.blockquoteDecoration!,
            child: Padding(
              padding: styleSheet.blockquotePadding!,
              child: child,
            ),
          );
        } catch (e) {
          // Fallback to simple container if decoration fails
          child = Container(
            padding: const EdgeInsets.all(8),
            child: child,
          );
        }
      } else if (tag == 'pre') {
        try {
          final codeText = getElementText(element);
          final lang = detectLanguage(codeText);
          child = Container(
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6.0),
                border: Border.all(color: Color(0xFFCACACA), width: 0.5)
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.max,
              children: [
                Container(
                  height: 33,
                  decoration: BoxDecoration(
                      color: Color(0xFFEEEEEE).withOpacity(0.55),
                      borderRadius: BorderRadius.only(topLeft: Radius.circular(6.0), topRight: Radius.circular(6.0))
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Padding(
                        padding: EdgeInsets.only(left: 16),
                        child: Text(lang == 'plaintext' ? 'Code Block' : lang, style: TextStyle(
                            color: Color(0xFF464648),
                            fontWeight: FontWeight.w400,
                            fontSize: 13,
                            fontFamily: 'Roboto',
                            decoration: TextDecoration.none).copyWith(
                          fontWeight: FontWeight.w500, color: Color(0xFF464648)),),
                      ),
                      GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: (){
                            try {
                              Clipboard.setData(ClipboardData(
                                  text: codeText));
                              CopyToastCustom.show(delegate.context);
                            } catch (e) {
                              // Fallback if clipboard or toast fails
                            }
                          },
                          child: Padding(
                            padding: EdgeInsets.only(right: 16),
                            child: Row(children: [
                              SvgPicture.asset(
                                'assets/icons/ic_copy_code.svg',
                                fit: BoxFit.cover,
                                package: 'flutter_markdown',
                                width: 16,
                                height: 16,
                                placeholderBuilder: (context) => const Icon(Icons.copy, size: 16),
                              ),
                              const SizedBox(width: 8,),
                              Text("Sao chép", style: TextStyle(
                                  color: Color(0xFF464648),
                                  fontWeight: FontWeight.w400,
                                  fontSize: 13,
                                  fontFamily: 'Roboto',
                                  decoration: TextDecoration.none))
                            ],),
                          )
                      )
                    ],
                  ),
                ),
                child
              ],
            ),
          );
        } catch (e) {
          // Fallback to simple code block if custom styling fails
          child = Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFFAFAFA),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: child,
          );
        }
      } else if (tag == 'hr') {
        try {
          child = Container(
            decoration: styleSheet.horizontalRuleDecoration, 
            margin: const EdgeInsets.only(top: 20, bottom: 20),
          );
        } catch (e) {
          // Fallback to simple horizontal rule
          child = Container(
            height: 1,
            color: Colors.grey.shade300,
            margin: const EdgeInsets.only(top: 20, bottom: 20),
          );
        }
      }

      _addBlockChild(child);
    } else {
      final _InlineElement current = _inlines.removeLast();
      final _InlineElement parent = _inlines.last;
      EdgeInsets padding = EdgeInsets.zero;

      if (paddingBuilders.containsKey(tag)) {
        padding = paddingBuilders[tag]!.getPadding();
      }

      if (builders.containsKey(tag)) {
        final Widget? child = builders[tag]!.visitElementAfterWithContext(
          delegate.context,
          element,
          styleSheet.styles[tag],
          parent.style,
        );
        if (child != null) {
          if (current.children.isEmpty) {
            current.children.add(child);
          } else {
            current.children[0] = child;
          }
        }
      } else if (tag == 'img') {
        // create an image widget for this image
        current.children.add(_buildPadding(
          padding,
          _buildImage(
            element.attributes['src']!,
            element.attributes['title'],
            element.attributes['alt'],
          ),
        ));
      } else if (tag == 'br') {
        current.children.add(_buildRichText(const TextSpan(text: '\n')));
      } else if (tag == 'th' || tag == 'td') {
        TextAlign? align;
        final String? alignAttribute = element.attributes['align'];
        if (alignAttribute == null) {
          align = tag == 'th' ? styleSheet.tableHeadAlign : TextAlign.left;
        } else {
          switch (alignAttribute) {
            case 'left':
              align = TextAlign.left;
            case 'center':
              align = TextAlign.center;
            case 'right':
              align = TextAlign.right;
          }
        }
        final Widget child = _buildTableCell(
          _mergeInlineChildren(current.children, align),
          textAlign: align,
        );
        _tables.single.rows.last.children.add(child);
      } else if (tag == 'a') {
        _linkHandlers.removeLast();
      } else if (tag == 'sup') {
        final Widget c = current.children.last;
        TextSpan? textSpan;
        if (c is Text && c.textSpan is TextSpan) {
          textSpan = c.textSpan! as TextSpan;
        } else if (c is SelectableText && c.textSpan is TextSpan) {
          textSpan = c.textSpan;
        }
        if (textSpan != null) {
          final Widget richText = _buildRichText(
            TextSpan(
              recognizer: textSpan.recognizer,
              text: element.textContent,
              style: textSpan.style?.copyWith(
                fontFeatures: <FontFeature>[
                  const FontFeature.enable('sups'),
                  if (styleSheet.superscriptFontFeatureTag != null)
                    FontFeature.enable(styleSheet.superscriptFontFeatureTag!),
                ],
              ),
            ),
          );
          current.children.removeLast();
          current.children.add(richText);
        }
      }

      if (current.children.isNotEmpty) {
        parent.children.addAll(current.children);
      }
    }
    if (_currentBlockTag == tag) {
      _currentBlockTag = null;
    }
    _lastVisitedTag = tag;
  }

  String getElementText(md.Element element) {
    try {
      final buffer = StringBuffer();

      void extractText(md.Node node) {
        if (node is md.Text) {
          buffer.write(node.text);
        } else if (node is md.Element && node.children != null) {
          for (final child in node.children!) {
            extractText(child);
          }
        }
      }

      extractText(element);
      return buffer.toString();
    } catch (e) {
      // Fallback to empty string if text extraction fails
      return '';
    }
  }

  Table _buildTable() {
    try {
      return Table(
        columnWidths: {
          1: const MaxColumnWidth(
            IntrinsicColumnWidth(),
            FixedColumnWidth(190), // max 190
          ),
        },
        defaultColumnWidth: styleSheet.tableColumnWidth!,
        defaultVerticalAlignment: styleSheet.tableVerticalAlignment,
        border: styleSheet.tableBorder,
        children: _tables.removeLast().rows.map((row) {
          return TableRow(
            children: row.children.map((cell) {
              return TableCell(
                verticalAlignment: TableCellVerticalAlignment.middle,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 190),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: DefaultTextStyle.merge(
                      softWrap: true,
                      overflow: TextOverflow.visible,
                      child: cell, // 👈 chính là widget gốc
                    ),
                  ),
                ),
              );
            }).toList(),
          );
        }).toList(),
      );
    } catch (e) {
      // Fallback to simple table if complex table fails
      return Table(
        border: TableBorder.all(color: Colors.grey.shade300),
        children: _tables.removeLast().rows.map((row) {
          return TableRow(
            children: row.children.map((cell) {
              return TableCell(
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: cell,
                ),
              );
            }).toList(),
          );
        }).toList(),
      );
    }
  }


  Widget _buildImage(String src, String? title, String? alt) {
    try {
      final List<String> parts = src.split('#');
      if (parts.isEmpty) {
        return const SizedBox();
      }

      final String path = parts.first;
      double? width;
      double? height;
      if (parts.length == 2) {
        final List<String> dimensions = parts.last.split('x');
        if (dimensions.length == 2) {
          width = double.tryParse(dimensions[0]);
          height = double.tryParse(dimensions[1]);
        }
      }

      final Uri? uri = Uri.tryParse(path);

      if (uri == null) {
        return const SizedBox();
      }

      Widget child;
      if (sizedImageBuilder != null) {
        final MarkdownImageConfig config = MarkdownImageConfig(
            uri: uri, alt: alt, title: title, height: height, width: width);
        child = sizedImageBuilder!(config);
      } else if (imageBuilder != null) {
        child = imageBuilder!(uri, alt, title);
      } else {
        child = kDefaultImageBuilder(uri, imageDirectory, width, height);
      }

      if (_linkHandlers.isNotEmpty) {
        final TapGestureRecognizer recognizer =
        _linkHandlers.last as TapGestureRecognizer;
        return GestureDetector(onTap: recognizer.onTap, child: child);
      } else {
        return child;
      }
    } catch (e) {
      // Fallback to simple text if image building fails
      return Text(alt ?? 'Image');
    }
  }

  Widget _buildCheckbox(bool checked) {
    if (checkboxBuilder != null) {
      return checkboxBuilder!(checked);
    }
    return Padding(
      padding: styleSheet.listBulletPadding!,
      child: Icon(
        checked ? Icons.check_box : Icons.check_box_outline_blank,
        size: styleSheet.checkbox!.fontSize,
        color: styleSheet.checkbox!.color,
      ),
    );
  }

  Widget _buildBullet(String listTag) {
    final int index = _blocks.last.nextListIndex;
    final bool isUnordered = listTag == 'ul';

    if (bulletBuilder != null) {
      return Padding(
        padding: styleSheet.listBulletPadding!,
        child: bulletBuilder!(
          MarkdownBulletParameters(
            index: index,
            style: isUnordered
                ? BulletStyle.unorderedList
                : BulletStyle.orderedList,
            nestLevel: _listIndents.length - 1,
          ),
        ),
      );
    }

    if (isUnordered) {
      return Padding(
        padding: styleSheet.listBulletPadding!,
        child: Text(
          '•',
          textAlign: TextAlign.center,
          style: styleSheet.listBullet,
        ),
      );
    }

    return Padding(
      padding: styleSheet.listBulletPadding!,
      child: Text(
        '${index + 1}.',
        textAlign: TextAlign.right,
        style: styleSheet.listBullet,
      ),
    );
  }

  Widget _buildTableCell(List<Widget?> children, {TextAlign? textAlign}) {
    try {
      return TableCell(
        child: Padding(
          padding: styleSheet.tableCellsPadding!,
          child: DefaultTextStyle(
            style: styleSheet.tableBody!,
            textAlign: textAlign,
            child: Wrap(
              alignment: switch (textAlign) {
                TextAlign.left => WrapAlignment.start,
                TextAlign.center => WrapAlignment.center,
                TextAlign.right => WrapAlignment.end,
                _ => WrapAlignment.start,
              },
              children: children as List<Widget>,
            ),
          ),
        ),
      );
    } catch (e) {
      // Fallback to simple table cell if complex styling fails
      return TableCell(
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Wrap(
            children: children.whereType<Widget>().toList(),
          ),
        ),
      );
    }
  }

  Widget _buildPadding(EdgeInsets padding, Widget child) {
    if (padding == EdgeInsets.zero) {
      return child;
    }

    return Padding(padding: padding, child: child);
  }

  void _addParentInlineIfNeeded(String? tag) {
    if (_inlines.isEmpty) {
      _inlines.add(_InlineElement(
        tag,
        style: styleSheet.styles[tag!],
      ));
    }
  }

  void _addBlockChild(Widget child) {
    final _BlockElement parent = _blocks.last;
    if (parent.children.isNotEmpty) {
      parent.children.add(SizedBox(height: styleSheet.blockSpacing));
    }
    parent.children.add(child);
    parent.nextListIndex += 1;
  }

  void _addAnonymousBlockIfNeeded() {
    if (_inlines.isEmpty) {
      return;
    }

    WrapAlignment blockAlignment = WrapAlignment.start;
    TextAlign textAlign = TextAlign.start;
    EdgeInsets textPadding = EdgeInsets.zero;
    if (_isBlockTag(_currentBlockTag)) {
      blockAlignment = _wrapAlignmentForBlockTag(_currentBlockTag);
      textAlign = _textAlignForBlockTag(_currentBlockTag);
      textPadding = _textPaddingForBlockTag(_currentBlockTag);

      if (paddingBuilders.containsKey(_currentBlockTag)) {
        textPadding = paddingBuilders[_currentBlockTag]!.getPadding();
      }
    }

    final _InlineElement inline = _inlines.single;
    if (inline.children.isNotEmpty) {
      final List<Widget> mergedInlines = _mergeInlineChildren(
        inline.children,
        textAlign,
      );
      final Wrap wrap = Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: blockAlignment,
        children: mergedInlines,
      );

      if (textPadding == EdgeInsets.zero) {
        _addBlockChild(wrap);
      } else {
        final Padding padding = Padding(padding: textPadding, child: wrap);
        _addBlockChild(padding);
      }

      _inlines.clear();
    }
  }

  /// Extracts all spans from an inline element and merges them into a single list
  Iterable<InlineSpan> _getInlineSpansFromSpan(InlineSpan span) {
    // If the span is not a TextSpan or it has no children, return the span
    if (span is! TextSpan || span.children == null) {
      return <InlineSpan>[span];
    }

    // Merge the style of the parent with the style of the children
    final Iterable<InlineSpan> spans =
    span.children!.map((InlineSpan childSpan) {
      if (childSpan is TextSpan) {
        return TextSpan(
          text: childSpan.text,
          recognizer: childSpan.recognizer,
          semanticsLabel: childSpan.semanticsLabel,
          style: childSpan.style?.merge(span.style),
        );
      } else {
        return childSpan;
      }
    });

    return spans;
  }

  // Accesses the TextSpan property correctly depending on the widget type.
  // Returns null if not a valid (text) widget.
  InlineSpan? _getInlineSpanFromText(Widget widget) => switch (widget) {
    SelectableText() => widget.textSpan,
    Text() => widget.textSpan,
    RichText() => widget.text,
    _ => null
  };

  /// Merges adjacent [TextSpan] children.
  /// Also forces a specific [TextAlign] regardless of merging.
  /// This is essential for table column alignment, since desired column alignment
  /// is discovered after the text widgets have been created. This function is the
  /// last chance to enforce the desired column alignment in the texts.
  List<Widget> _mergeInlineChildren(
      List<Widget> children,
      TextAlign? textAlign,
      ) {
    // List of text widgets (merged) and non-text widgets (non-merged)
    final List<Widget> mergedWidgets = <Widget>[];

    bool lastIsText = false;
    for (final Widget child in children) {
      final InlineSpan? currentSpan = _getInlineSpanFromText(child);
      final bool currentIsText = currentSpan != null;

      if (!currentIsText) {
        // There is no merging to do, so just add and continue
        mergedWidgets.add(child);
        lastIsText = false;
        continue;
      }

      // Extracted spans from the last and the current widget
      List<InlineSpan> spans = <InlineSpan>[];

      if (lastIsText) {
        // Removes last widget from the list for merging and extracts its spans
        spans.addAll(_getInlineSpansFromSpan(
            _getInlineSpanFromText(mergedWidgets.removeLast())!));
      }

      spans.addAll(_getInlineSpansFromSpan(currentSpan));
      spans = _mergeSimilarTextSpans(spans);

      final Widget mergedWidget;

      if (spans.isEmpty) {
        // no spans found, just insert the current widget
        mergedWidget = child;
      } else {
        final InlineSpan first = spans.first;
        final TextSpan textSpan = (spans.length == 1 && first is TextSpan)
            ? first
            : TextSpan(children: spans);
        mergedWidget = _buildRichText(textSpan, textAlign: textAlign);
      }

      mergedWidgets.add(mergedWidget);
      lastIsText = true;
    }

    return mergedWidgets;
  }

  TextAlign _textAlignForBlockTag(String? blockTag) {
    final WrapAlignment wrapAlignment = _wrapAlignmentForBlockTag(blockTag);
    switch (wrapAlignment) {
      case WrapAlignment.start:
        return TextAlign.start;
      case WrapAlignment.center:
        return TextAlign.center;
      case WrapAlignment.end:
        return TextAlign.end;
      case WrapAlignment.spaceAround:
        return TextAlign.justify;
      case WrapAlignment.spaceBetween:
        return TextAlign.justify;
      case WrapAlignment.spaceEvenly:
        return TextAlign.justify;
    }
  }

  WrapAlignment _wrapAlignmentForBlockTag(String? blockTag) {
    switch (blockTag) {
      case 'p':
        return styleSheet.textAlign;
      case 'h1':
        return styleSheet.h1Align;
      case 'h2':
        return styleSheet.h2Align;
      case 'h3':
        return styleSheet.h3Align;
      case 'h4':
        return styleSheet.h4Align;
      case 'h5':
        return styleSheet.h5Align;
      case 'h6':
        return styleSheet.h6Align;
      case 'ul':
        return styleSheet.unorderedListAlign;
      case 'ol':
        return styleSheet.orderedListAlign;
      case 'blockquote':
        return styleSheet.blockquoteAlign;
      case 'pre':
        return styleSheet.codeblockAlign;
      case 'hr':
        break;
      case 'li':
        break;
    }
    return WrapAlignment.start;
  }

  EdgeInsets _textPaddingForBlockTag(String? blockTag) {
    switch (blockTag) {
      case 'p':
        return styleSheet.pPadding!;
      case 'h1':
        return styleSheet.h1Padding!;
      case 'h2':
        return styleSheet.h2Padding!;
      case 'h3':
        return styleSheet.h3Padding!;
      case 'h4':
        return styleSheet.h4Padding!;
      case 'h5':
        return styleSheet.h5Padding!;
      case 'h6':
        return styleSheet.h6Padding!;
    }
    return EdgeInsets.zero;
  }

  /// Combine text spans with equivalent properties into a single span.
  List<InlineSpan> _mergeSimilarTextSpans(List<InlineSpan> textSpans) {
    if (textSpans.length < 2) {
      return textSpans;
    }

    final List<InlineSpan> mergedSpans = <InlineSpan>[];

    for (int index = 1; index < textSpans.length; index++) {
      final InlineSpan previous =
      mergedSpans.isEmpty ? textSpans.first : mergedSpans.removeLast();
      final InlineSpan nextChild = textSpans[index];

      final bool previousIsTextSpan = previous is TextSpan;
      final bool nextIsTextSpan = nextChild is TextSpan;
      if (!previousIsTextSpan || !nextIsTextSpan) {
        mergedSpans.addAll(<InlineSpan>[previous, nextChild]);
        continue;
      }

      final bool matchStyle = nextChild.recognizer == previous.recognizer &&
          nextChild.semanticsLabel == previous.semanticsLabel &&
          nextChild.style == previous.style;

      if (matchStyle) {
        mergedSpans.add(TextSpan(
          text: previous.toPlainText() + nextChild.toPlainText(),
          recognizer: previous.recognizer,
          semanticsLabel: previous.semanticsLabel,
          style: previous.style,
        ));
      } else {
        mergedSpans.addAll(<InlineSpan>[previous, nextChild]);
      }
    }

    // When the mergered spans compress into a single TextSpan return just that
    // TextSpan, otherwise bundle the set of TextSpans under a single parent.
    return mergedSpans;
  }

  Widget _buildRichText(TextSpan text, {TextAlign? textAlign, String? key}) {
    //Adding a unique key prevents the problem of using the same link handler for text spans with the same text
    final Key k = key == null ? UniqueKey() : Key(key);
    if (selectable) {
      return SelectableText.rich(
        text,
        textScaler: styleSheet.textScaler,
        textAlign: textAlign ?? TextAlign.start,
        onSelectionChanged: onSelectionChanged != null
            ? (TextSelection selection, SelectionChangedCause? cause) =>
            onSelectionChanged!(text.text, selection, cause)
            : null,
        onTap: onTapText,
        key: k,
      );
    } else {
      return Text.rich(
        text,
        textScaler: styleSheet.textScaler,
        textAlign: textAlign ?? TextAlign.start,
        key: k,
      );
    }
  }
}

class _ScrollControllerBuilder extends StatefulWidget {
  const _ScrollControllerBuilder({
    required this.builder,
    this.child,
  });

  final ValueWidgetBuilder<ScrollController> builder;

  final Widget? child;

  @override
  State<_ScrollControllerBuilder> createState() =>
      _ScrollControllerBuilderState();
}

class _ScrollControllerBuilderState extends State<_ScrollControllerBuilder> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _controller, widget.child);
  }
}

class MaxIntrinsicColumnWidth extends TableColumnWidth {
  final double maxWidth;

  const MaxIntrinsicColumnWidth(this.maxWidth);

  @override
  double minIntrinsicWidth(Iterable<RenderBox> cells, double containerWidth) {
    final intrinsic = IntrinsicColumnWidth().minIntrinsicWidth(cells, containerWidth);
    return intrinsic.clamp(0, maxWidth);
  }

  @override
  double maxIntrinsicWidth(Iterable<RenderBox> cells, double containerWidth) {
    final intrinsic = IntrinsicColumnWidth().maxIntrinsicWidth(cells, containerWidth);
    return intrinsic.clamp(0, maxWidth);
  }

  @override
  double flex(Iterable<RenderBox> cells) => 0.0;
}

class CopyToastCustom {
  static OverlayEntry? _overlayEntry;

  static void show(BuildContext? context,
      {String text = 'Đã sao chép', double? paddingTop, double width = 183}) {
    try {
      if (context == null) return;
      remove(); // always remove old one

      _overlayEntry = OverlayEntry(
        builder: (context) => Positioned(
          top: paddingTop ?? (MediaQuery.of(context).viewPadding.top + 62),
          left: MediaQuery.of(context).size.width * 0.2,
          right: MediaQuery.of(context).size.width * 0.2,
          child: _ToastContent(
            text: text,
            width: width,
          ),
        ),
      );

      Overlay.of(context).insert(_overlayEntry!);

      Future.delayed(const Duration(seconds: 2), () {
        remove();
      });
    } catch (e) {
      // Fallback if toast fails
    }
  }

  static void remove() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }
}

class _ToastContent extends StatefulWidget {
  final String text;
  final double width;

  const _ToastContent({required this.text, this.width = 183});

  @override
  State<_ToastContent> createState() => _ToastContentState();
}

class _ToastContentState extends State<_ToastContent>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _fade = Tween<double>(begin: 0, end: 1).animate(_controller);

    // Start animation after frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: Material(
        color: Colors.transparent,
        child: Center(
          child: Container(
            //width: widget.width,
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 13),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                    offset: const Offset(2, 2),
                    blurRadius: 12,
                    spreadRadius: 4,
                    color: Color(0xFFCACACA).withOpacity(0.3)),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SvgPicture.asset(
                  'assets/icons/ic_copyed.svg',
                  fit: BoxFit.cover,
                  package: 'flutter_markdown',
                  width: 24,
                  height: 24,
                  placeholderBuilder: (context) => const Icon(Icons.check, size: 24),
                ),
                const SizedBox(width: 10),
                Text(
                  widget.text,
                  style: TextStyle(
                      color: Color(0xFF4F4F4F),
                      fontWeight: FontWeight.w400,
                      fontSize: 15,
                      decoration: TextDecoration.none),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () {
                    CopyToastCustom.remove();
                  },
                  behavior: HitTestBehavior.translucent,
                  child: SvgPicture.asset(
                    'assets/icons/ic_close_copy.svg',
                    fit: BoxFit.cover,
                    package: 'flutter_markdown',
                    width: 24,
                    height: 24,
                    placeholderBuilder: (context) => const Icon(Icons.close, size: 24),
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}