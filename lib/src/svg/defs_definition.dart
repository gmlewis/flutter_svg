import 'dart:ui';

import 'package:path_drawing/path_drawing.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:xml/xml.dart';

import '../utilities/xml.dart';
import './parsers.dart';
import './xml_parsers.dart';

class DefsDefinition {
  DefsDefinition({
    this.clipPath,
    this.dashArray,
    this.dashOffset,
    this.fill,
    this.fillOpacity,
    this.fillRule,
    this.fontFamily,
    this.fontSize,
    this.opacity,
    this.path,
    this.stroke,
    this.strokeLinecap,
    this.strokeLinejoin,
    this.strokeMiterlimit,
    this.strokeOpacity,
    this.strokeWidth,
    this.transform,
    this.transformedPath,
  });

  factory DefsDefinition.parse(XmlElement el) {
    final SvgPathFactory pathFactory = svgPathParsers[el.name.local];
    if (pathFactory == null) {
      return null;
    }

    final Path path = pathFactory(el);
    final Path transformedPath = applyTransformIfNeeded(path, el);
    final Matrix4 transform = parseTransform(getAttribute(el, 'transform'));
    return new DefsDefinition(
      clipPath: getAttribute(el, 'clipPath'),
      dashArray: parseDashArray(el),
      dashOffset: parseDashOffset(el),
      fill: getAttribute(el, 'fill'),
      fillOpacity: getAttribute(el, 'fillOpacity'),
      fillRule: parseFillRule(el),
      fontFamily: getAttribute(el, 'fontFamily'),
      fontSize: getAttribute(el, 'fontSize'),
      opacity: parseOpacity(el),
      path: path,
      stroke: getAttribute(el, 'stroke'),
      strokeLinecap: getAttribute(el, 'strokeLinecap'),
      strokeLinejoin: getAttribute(el, 'strokeLinejoin'),
      strokeMiterlimit: getAttribute(el, 'strokeMiterlimit'),
      strokeOpacity: getAttribute(el, 'strokeOpacity'),
      strokeWidth: getAttribute(el, 'strokeWidth'),
      transform: transform,
      transformedPath: transformedPath,
    );
  }

  final String clipPath;
  final CircularIntervalList<double> dashArray;
  final DashOffset dashOffset;
  final String fill;
  final String fillOpacity;
  final PathFillType fillRule;
  final String fontFamily;
  final String fontSize;
  final double opacity;
  final Path path;
  final String stroke;
  final String strokeLinecap;
  final String strokeLinejoin;
  final String strokeMiterlimit;
  final String strokeOpacity;
  final String strokeWidth;
  final Matrix4 transform;
  final Path transformedPath;
}
