import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart';
import 'package:vector_math/vector_math_64.dart';

import 'svg/colors.dart';
import 'svg/defs_definition.dart';
import 'svg/parsers.dart';
import 'svg/xml_parsers.dart';
import 'utilities/xml.dart';
import 'vector_drawable.dart';

/// An SVG Shape element that will be drawn to the canvas.
class DrawableSvgShape extends DrawableShape {
  const DrawableSvgShape(Path path, DrawableStyle style) : super(path, style);

  /// Applies the transformation in the @transform attribute to the path.
  factory DrawableSvgShape.parse(
      SvgPathFactory pathFactory,
      DrawableDefinitionServer definitions,
      XmlElement el,
      DrawableStyle parentStyle) {
    assert(pathFactory != null);

    final Color defaultFill = parentStyle == null || parentStyle.fill == null
        ? colorBlack
        : identical(parentStyle.fill, DrawableStyle.emptyPaint)
            ? null
            : parentStyle.fill.color;

    final Color defaultStroke =
        identical(parentStyle.stroke, DrawableStyle.emptyPaint)
            ? null
            : parentStyle?.stroke?.color;

    // print(defaultStroke);

    final Path path = pathFactory(el);
    return new DrawableSvgShape(
      applyTransformIfNeeded(path, el),
      parseStyle(el, definitions, path.getBounds(), parentStyle,
          defaultFillIfNotSpecified: defaultFill,
          defaultStrokeIfNotSpecified: defaultStroke),
    );
  }

  /// Generates DrawableSvgShape from saved <defs>.
  factory DrawableSvgShape.fromDefs(
      String id,
      DefsDefinitionServer defsDefinitions,
      DrawableDefinitionServer definitions,
      DrawableStyle parentStyle) {
    assert(id != null && id != '');
    if (!defsDefinitions.containsKey(id)) {
      return null;
    }

    final DefsDefinition defsDefinition = defsDefinitions.get(id);

    final Color defaultFill = parentStyle == null || parentStyle.fill == null
        ? colorBlack
        : identical(parentStyle.fill, DrawableStyle.emptyPaint)
            ? null
            : parentStyle.fill.color;

    final Color defaultStroke =
        identical(parentStyle.stroke, DrawableStyle.emptyPaint)
            ? null
            : parentStyle?.stroke?.color;

    // print(defaultStroke);

    final Path path = defsDefinition.path;
    return new DrawableSvgShape(
      defsDefinition.transformedPath,
      parseStyleFromDefs(
          defsDefinition, definitions, path.getBounds(), parentStyle,
          defaultFillIfNotSpecified: defaultFill,
          defaultStrokeIfNotSpecified: defaultStroke),
    );
  }
}

/// Creates a [Drawable] from an SVG <g> or shape element.  Also handles parsing <defs> and gradients.
///
/// If an unsupported element is encountered, it will be created as a [DrawableNoop].
Drawable parseSvgElement(
    XmlElement el,
    DefsDefinitionServer defsDefinitions,
    DrawableDefinitionServer definitions,
    Rect bounds,
    DrawableStyle parentStyle,
    String key) {
  final Function unhandled = (XmlElement e) => _unhandledElement(e, key);

  final SvgPathFactory shapeFn = svgPathParsers[el.name.local];
  if (shapeFn != null) {
    return new DrawableSvgShape.parse(shapeFn, definitions, el, parentStyle);
  } else if (el.name.local == 'defs') {
    final Iterable<XmlElement> defs = parseDefs(el, definitions);
    for (XmlElement def in defs) {
      final String id = getAttribute(def, 'id');
      if (id != null) {
        final DefsDefinition defsDefinition = DefsDefinition.parse(def);
        if (defsDefinition != null) {
          defsDefinitions.add(id, defsDefinition);
        } else {
          unhandled(def);
        }
      } else {
        unhandled(def);
      }
    }
    return new DrawableNoop(el.name.local);
  } else if (el.name.local.endsWith('Gradient')) {
    definitions.addPaintServer(
        'url(#${getAttribute(el, 'id')})', parseGradient(el));
    return new DrawableNoop(el.name.local);
  } else if (el.name.local == 'g' || el.name.local == 'a') {
    return parseSvgGroup(
        el, defsDefinitions, definitions, bounds, parentStyle, key);
  } else if (el.name.local == 'text') {
    return parseSvgText(el, definitions, bounds, parentStyle);
  } else if (el.name.local == 'use') {
    String id = getAttribute(el, 'xlink:href');
    if (id != null) {
      if (id.startsWith('#')) {
        id = id.substring(1); // Chop off '#'.
      }
      final DrawableSvgShape shape = new DrawableSvgShape.fromDefs(
          id, defsDefinitions, definitions, parentStyle);
      if (shape != null) {
        return shape;
      }
    }
    unhandled(el);
    return new DrawableNoop(el.name.local);
  } else if (el.name.local == 'svg') {
    throw new UnsupportedError(
        'Nested SVGs not supported in this implementation.');
  }

  unhandled(el);
  return new DrawableNoop(el.name.local);
}

void _unhandledElement(XmlElement el, String key) {
  if (el.name.local == 'style') {
    FlutterError.reportError(new FlutterErrorDetails(
      exception: new UnimplementedError(
          'The <style> element is not implemented in this library.'),
      informationCollector: (StringBuffer buff) {
        buff.writeln(
            'Style elements are not supported by this library and the requested SVG may not '
            'render as intended.\n'
            'If possible, ensure the SVG uses inline styles and/or attributes (which are '
            'supported), or use a preprocessing utility such as svgcleaner to inline the '
            'styles for you.');
        buff.writeln();
        buff.writeln('Picture key: $key');
      },
      library: 'SVG',
      context: 'in parseSvgElement',
    ));
  } else if (el.name.local != 'desc') {
    // no plans to handle these
    print('unhandled element ${el.name.local}; Picture key: $key');
  }
}

Paint _transparentPaint = new Paint()..color = const Color(0x0);
void _appendParagraphs(ParagraphBuilder fill, ParagraphBuilder stroke,
    String text, DrawableStyle style) {
  fill
    ..pushStyle(style.textStyle.buildTextStyle(foregroundOverride: style.fill))
    ..addText(text);

  stroke
    ..pushStyle(style.textStyle.buildTextStyle(
        foregroundOverride:
            style.stroke == null ? _transparentPaint : style.stroke))
    ..addText(text);
}

final ParagraphConstraints _infiniteParagraphConstraints =
    new ParagraphConstraints(width: double.infinity);

Paragraph _finishParagraph(ParagraphBuilder paragraphBuilder) {
  final Paragraph paragraph = paragraphBuilder.build();
  paragraph.layout(_infiniteParagraphConstraints);
  return paragraph;
}

void _paragraphParser(
    ParagraphBuilder fill,
    ParagraphBuilder stroke,
    DrawableDefinitionServer definitions,
    Rect bounds,
    XmlNode parent,
    DrawableStyle style) {
  for (XmlNode child in parent.children) {
    switch (child.nodeType) {
      case XmlNodeType.CDATA:
      case XmlNodeType.TEXT:
        // print(style.stroke);
        _appendParagraphs(fill, stroke, child.text, style);
        break;
      case XmlNodeType.ELEMENT:
        final DrawableStyle childStyle =
            parseStyle(child, definitions, bounds, style);
        _paragraphParser(fill, stroke, definitions, bounds, child, childStyle);
        fill.pop();
        stroke.pop();
        break;
      default:
        break;
    }
  }
}

Drawable parseSvgText(XmlElement el, DrawableDefinitionServer definitions,
    Rect bounds, DrawableStyle parentStyle) {
  final Offset offset = new Offset(
      double.parse(getAttribute(el, 'x', def: '0')),
      double.parse(getAttribute(el, 'y', def: '0')));

  final DrawableStyle style = parseStyle(el, definitions, bounds, parentStyle);

  final ParagraphBuilder fill = new ParagraphBuilder(new ParagraphStyle());
  final ParagraphBuilder stroke = new ParagraphBuilder(new ParagraphStyle());

  final DrawableTextAnchorPosition textAnchor =
      parseTextAnchor(getAttribute(el, 'text-anchor', def: 'start'));

  if (el.children.length == 1) {
    _appendParagraphs(fill, stroke, el.text, style);

    return new DrawableText(
      _finishParagraph(fill),
      _finishParagraph(stroke),
      offset,
      textAnchor,
    );
  }

  _paragraphParser(fill, stroke, definitions, bounds, el, style);

  return new DrawableText(
    _finishParagraph(fill),
    _finishParagraph(stroke),
    offset,
    textAnchor,
  );
}

/// Parses an SVG <g> element.
Drawable parseSvgGroup(
    XmlElement el,
    DefsDefinitionServer defsDefinitions,
    DrawableDefinitionServer definitions,
    Rect bounds,
    DrawableStyle parentStyle,
    String key) {
  final List<Drawable> children = <Drawable>[];
  final DrawableStyle style =
      parseStyle(el, definitions, bounds, parentStyle, needsTransform: true);
  for (XmlNode child in el.children) {
    if (child is XmlElement) {
      final Drawable el = parseSvgElement(
          child, defsDefinitions, definitions, bounds, style, key);
      if (el != null) {
        children.add(el);
      }
    }
  }

  return new DrawableGroup(
      children,
      //TODO: when Dart2 is around use this instead of above
      // el.children
      //     .whereType<XmlElement>()
      //     .map((child) => new SvgBaseElement.fromXml(child)),
      style);
}

/// Parses style attributes or @style attribute.
///
/// Remember that @style attribute takes precedence.
DrawableStyle parseStyle(XmlElement el, DrawableDefinitionServer definitions,
    Rect bounds, DrawableStyle parentStyle,
    {bool needsTransform = false,
    Color defaultFillIfNotSpecified,
    Color defaultStrokeIfNotSpecified}) {
  final Matrix4 transform =
      needsTransform ? parseTransform(getAttribute(el, 'transform')) : null;

  return DrawableStyle.mergeAndBlend(
    parentStyle,
    transform: transform?.storage,
    stroke: parseStroke(el, bounds, definitions, defaultStrokeIfNotSpecified),
    dashArray: parseDashArray(el),
    dashOffset: parseDashOffset(el),
    fill: parseFill(el, bounds, definitions, defaultFillIfNotSpecified),
    pathFillType: parseFillRule(el),
    groupOpacity: parseOpacity(el),
    clipPath: parseClipPath(el, definitions),
    textStyle: new DrawableTextStyle(
      fontFamily: getAttribute(el, 'font-family'),
      fontSize: parseFontSize(getAttribute(el, 'font-size'),
          parentValue: parentStyle?.textStyle?.fontSize),
      height: -1.0,
    ),
  );
}

/// Parses style attributes or @style attribute.
///
/// Remember that @style attribute takes precedence.
DrawableStyle parseStyleFromDefs(
    DefsDefinition defsDefinition,
    DrawableDefinitionServer definitions,
    Rect bounds,
    DrawableStyle parentStyle,
    {bool needsTransform = false,
    Color defaultFillIfNotSpecified,
    Color defaultStrokeIfNotSpecified}) {
  final Matrix4 transform = needsTransform ? defsDefinition.transform : null;

  return DrawableStyle.mergeAndBlend(
    parentStyle,
    transform: transform?.storage,
    stroke: parseStrokeFromDefs(
        defsDefinition, bounds, definitions, defaultStrokeIfNotSpecified),
    dashArray: defsDefinition.dashArray,
    dashOffset: defsDefinition.dashOffset,
    fill: parseFillFromDefs(
        defsDefinition, bounds, definitions, defaultFillIfNotSpecified),
    pathFillType: defsDefinition.fillRule,
    groupOpacity: defsDefinition.opacity,
    clipPath: parseClipPathFromDefs(defsDefinition, definitions),
    textStyle: new DrawableTextStyle(
      fontFamily: defsDefinition.fontFamily,
      fontSize: parseFontSize(defsDefinition.fontSize,
          parentValue: parentStyle?.textStyle?.fontSize),
      height: -1.0,
    ),
  );
}

// Contains DefsDefinitions that can be referenced by a String ID.
class DefsDefinitionServer {
  final Map<String, DefsDefinition> _defsDefinitions =
      <String, DefsDefinition>{};

  bool containsKey(String id) => _defsDefinitions.containsKey(id);

  DefsDefinition get(String id) {
    assert(id != null);
    return _defsDefinitions[id];
  }

  void add(String id, DefsDefinition el) {
    assert(id != null);
    _defsDefinitions[id] = el;
  }
}
