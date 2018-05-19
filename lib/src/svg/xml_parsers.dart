import 'dart:ui';

import 'package:path_drawing/path_drawing.dart';
import 'package:xml/xml.dart';

import '../utilities/xml.dart';
import '../vector_painter.dart';
import 'colors.dart';
import 'parsers.dart';

/// Parses an SVG @viewBox attribute (e.g. 0 0 100 100) to a [Rect].
Rect parseViewBox(XmlElement svg) {
  final String viewBox = getAttribute(svg, 'viewBox');

  if (viewBox == '') {
    final RegExp notDigits = new RegExp(r'[^\d\.]');
    final String rawWidth =
        getAttribute(svg, 'width').replaceAll(notDigits, '');
    final String rawHeight =
        getAttribute(svg, 'height').replaceAll(notDigits, '');
    if (rawWidth == '' || rawHeight == '') {
      return Rect.zero;
    }
    final double width = double.parse(rawWidth);
    final double height = double.parse(rawHeight);
    return new Rect.fromLTWH(0.0, 0.0, width, height);
  }

  final List<String> parts = viewBox.split(new RegExp(r'[ ,]+'));
  if (parts.length < 4) {
    throw new StateError('viewBox element must be 4 elements long');
  }
  return new Rect.fromLTWH(
    double.parse(parts[0]),
    double.parse(parts[1]),
    double.parse(parts[2]),
    double.parse(parts[3]),
  );
}

String buildUrlIri(XmlElement def) => 'url(#${getAttribute(def, 'id')})';

/// Parses a <def> element, extracting <linearGradient> and (TODO) <radialGradient> elements into the `paintServers` map.
void parseDefs(XmlElement el, DrawableDefinitionServer definitions) {
  for (XmlNode def in el.children) {
    if (def is XmlElement) {
      if (def.name.local.endsWith('Gradient')) {
        definitions.addPaintServer(buildUrlIri(def), parseGradient(def));
      } else if (def.name.local == 'clipPath') {
        definitions.addClipPath(buildUrlIri(def), parseClipPath(def));
      }
    }
  }
}

double _parseDecimalOrPercentage(String val, {double multiplier = 1.0}) {
  if (val.endsWith('%')) {
    return double.parse(val.substring(0, val.length - 1)) / 100 * multiplier;
  } else {
    return double.parse(val);
  }
}

TileMode parseTileMode(XmlElement el) {
  final String spreadMethod = getAttribute(el, 'spreadMethod', def: 'pad');
  switch (spreadMethod) {
    case 'pad':
      return TileMode.clamp;
    case 'repeat':
      return TileMode.repeated;
    case 'reflect':
      return TileMode.mirror;
    default:
      return TileMode.clamp;
  }
}

void parseStops(
    List<XmlElement> stops, List<Color> colors, List<double> offsets) {
  for (int i = 0; i < stops.length; i++) {
    final String rawOpacity = getAttribute(stops[i], 'stop-opacity', def: '1');
    colors[i] = parseColor(getAttribute(stops[i], 'stop-color'))
        .withOpacity(double.parse(rawOpacity));

    final String rawOffset = getAttribute(stops[i], 'offset');
    offsets[i] = _parseDecimalOrPercentage(rawOffset);
  }
}

/// Parses an SVG <linearGradient> element into a [Paint].
PaintServer parseLinearGradient(XmlElement el) {
  final double x1 =
      _parseDecimalOrPercentage(getAttribute(el, 'x1', def: '0%'));
  final double x2 =
      _parseDecimalOrPercentage(getAttribute(el, 'x2', def: '100%'));
  final double y1 =
      _parseDecimalOrPercentage(getAttribute(el, 'y1', def: '0%'));
  final double y2 =
      _parseDecimalOrPercentage(getAttribute(el, 'y2', def: '0%'));

  final TileMode spreadMethod = parseTileMode(el);
  final List<XmlElement> stops = el.findElements('stop').toList();
  final List<Color> colors = new List<Color>(stops.length);
  final List<double> offsets = new List<double>(stops.length);

  parseStops(stops, colors, offsets);

  return (Rect bounds) {
    final Offset from = new Offset(
      bounds.left + (bounds.width * x1),
      bounds.left + (bounds.height * y1),
    );
    final Offset to = new Offset(
      bounds.left + (bounds.width * x2),
      bounds.left + (bounds.height * y2),
    );

    final Gradient gradient = new Gradient.linear(
      from,
      to,
      colors,
      offsets,
      spreadMethod,
    );

    return new Paint()..shader = gradient;
  };
}

/// Parses a <radialGradient> into a [Paint].
PaintServer parseRadialGradient(XmlElement el) {
  final String rawCx = getAttribute(el, 'cx', def: '50%');
  final String rawCy = getAttribute(el, 'cy', def: '50%');
  final TileMode spreadMethod = parseTileMode(el);

  final List<XmlElement> stops = el.findElements('stop').toList();

  final List<Color> colors = new List<Color>(stops.length);
  final List<double> offsets = new List<double>(stops.length);
  parseStops(stops, colors, offsets);

  return (Rect bounds) {
    final double cx = _parseDecimalOrPercentage(
      rawCx,
      multiplier: bounds.width + bounds.left + bounds.left,
    );
    final double cy = _parseDecimalOrPercentage(
      rawCy,
      multiplier: bounds.height + bounds.top + bounds.top,
    );
    final double r = _parseDecimalOrPercentage(
      getAttribute(el, 'r', def: '50%'),
      multiplier: (bounds.width + bounds.height) / 2,
    );
    final double fx = _parseDecimalOrPercentage(
      getAttribute(el, 'fx', def: rawCx),
      multiplier: bounds.width + (bounds.left * 2),
    );
    final double fy = _parseDecimalOrPercentage(
      getAttribute(el, 'fy', def: rawCy),
      multiplier: bounds.height + (bounds.top),
    );

    final Offset center = new Offset(cx, cy);
    final Offset focal =
        (fx != cx || fy != cy) ? new Offset(fx, fy) : new Offset(cx, cy);

    if (focal != center) {
      throw new UnsupportedError('Focal points not supported in this version');
    }

    final Gradient gradient = new Gradient.radial(
      center,
      r,
      colors,
      offsets,
      spreadMethod,
      null,
    );

    return new Paint()..shader = gradient;
  };
}

Path parseClipPath(XmlElement el) {
  return new Path();
}

/// Parses a <linearGradient> or <radialGradient> into a [Paint].
PaintServer parseGradient(XmlElement el) {
  if (el.name.local == 'linearGradient') {
    return parseLinearGradient(el);
  } else if (el.name.local == 'radialGradient') {
    return parseRadialGradient(el);
  }
  throw new StateError('Unknown gradient type ${el.name.local}');
}

/// Parses an @stroke-dasharray attribute into a [CircularIntervalList]
///
/// Does not currently support percentages.
CircularIntervalList<double> parseDashArray(XmlElement el) {
  final String rawDashArray = getAttribute(el, 'stroke-dasharray');
  if (rawDashArray == '') {
    return null;
  } else if (rawDashArray == 'none') {
    return DrawableStyle.emptyDashArray;
  }

  final List<String> parts = rawDashArray.split(new RegExp(r'[ ,]+'));
  return new CircularIntervalList<double>(
      parts.map((String part) => double.parse(part)).toList());
}

/// Parses a @stroke-dashoffset into a [DashOffset]
DashOffset parseDashOffset(XmlElement el) {
  final String rawDashOffset = getAttribute(el, 'stroke-dashoffset');
  if (rawDashOffset == '') {
    return null;
  }

  if (rawDashOffset.endsWith('%')) {
    final double percentage =
        double.parse(rawDashOffset.substring(0, rawDashOffset.length - 1)) /
            100;
    return new DashOffset.percentage(percentage);
  } else {
    return new DashOffset.absolute(double.parse(rawDashOffset));
  }
}

/// Parses an @opacity value into a [double], clamped between 0..1.
double parseOpacity(XmlElement el) {
  final String rawOpacity = getAttribute(el, 'opacity', def: null);
  if (rawOpacity != null) {
    return double.parse(rawOpacity).clamp(0.0, 1.0);
  }
  return null;
}

/// Parses a @stroke attribute into a [Paint].
Paint parseStroke(
    XmlElement el, Rect bounds, DrawableDefinitionServer definitions) {
  final String rawStroke = getAttribute(el, 'stroke');
  if (rawStroke == '') {
    return null;
  } else if (rawStroke == 'none') {
    return DrawableStyle.emptyPaint;
  }

  if (rawStroke.startsWith('url')) {
    return definitions.getPaint(rawStroke, bounds);
  }
  final String rawOpacity = getAttribute(el, 'stroke-opacity');

  final double opacity =
      rawOpacity == '' ? 1.0 : double.parse(rawOpacity).clamp(0.0, 1.0);
  final Paint paint = new Paint()
    ..color = parseColor(rawStroke).withOpacity(opacity)
    ..style = PaintingStyle.stroke;

  final String rawStrokeCap = getAttribute(el, 'stroke-linecap');
  paint.strokeCap = rawStrokeCap == 'null'
      ? StrokeCap.butt
      : StrokeCap.values.firstWhere(
          (StrokeCap sc) => sc.toString() == 'StrokeCap.$rawStrokeCap',
          orElse: () => StrokeCap.butt);

  final String rawLineJoin = getAttribute(el, 'stroke-linejoin');
  paint.strokeJoin = rawLineJoin == ''
      ? StrokeJoin.miter
      : StrokeJoin.values.firstWhere(
          (StrokeJoin sj) => sj.toString() == 'StrokeJoin.$rawLineJoin',
          orElse: () => StrokeJoin.miter);

  final String rawMiterLimit = getAttribute(el, 'stroke-miterlimit');
  paint.strokeMiterLimit =
      rawMiterLimit == '' ? 4.0 : double.parse(rawMiterLimit);

  final String rawStrokeWidth = getAttribute(el, 'stroke-width');
  paint.strokeWidth = rawStrokeWidth == '' ? 1.0 : double.parse(rawStrokeWidth);

  return paint;
}

Paint parseFill(XmlElement el, Rect bounds,
    DrawableDefinitionServer definitions, Color defaultFillIfNotSpecified) {
  final String rawFill = getAttribute(el, 'fill');
  if (rawFill == '') {
    if (defaultFillIfNotSpecified == null) {
      return null;
    }
    return new Paint()..color = defaultFillIfNotSpecified;
  } else if (rawFill == 'none') {
    return DrawableStyle.emptyPaint;
  }

  if (rawFill.startsWith('url')) {
    return definitions.getPaint(rawFill, bounds);
  }

  final String rawOpacity = getAttribute(el, 'fill-opacity');
  final double opacity = rawOpacity == ''
      ? rawFill == 'none' ? 0.0 : 1.0
      : double.parse(rawOpacity).clamp(0.0, 1.0);

  final Color fill = parseColor(rawFill).withOpacity(opacity);

  return new Paint()
    ..color = fill
    ..style = PaintingStyle.fill;
}

PathFillType parseFillRule(XmlElement el) {
  final String rawFillRule = getAttribute(el, 'fill-rule', def: 'nonzero');
  return parseRawFillRule(rawFillRule);
}
