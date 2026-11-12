import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

class ReaderPaperMesh {
  ReaderPaperMesh({
    required this.positions,
    required this.uv,
    required this.indices,
    required this.normals,
    required this.outline,
  });
  final Float32List positions, uv;
  final Uint16List indices;
  final List<double> normals;
  final Path outline;
}

/// A shared, bounded paper-strip mesh in hinge-local coordinates. The two faces
/// are complementary throughout the turn; UVs stay attached to the source leaf.
class ReaderPaperGeometry {
  ReaderPaperGeometry({
    required this.size,
    required this.gap,
    required double progress,
    required double touchY,
  }) {
    final p = progress.clamp(0.0, 1.0);
    lift = math.sin(p * math.pi).abs();
    final frontPositions = <double>[], backPositions = <double>[];
    final frontUV = <double>[], backUV = <double>[];
    final frontIndices = <int>[], backIndices = <int>[];
    final frontNormals = <double>[], backNormals = <double>[];
    final frontPath = Path(), backPath = Path();
    const strips = 32;
    final height = math.max(0.0, size.height),
        width = math.max(0.0, size.width);
    for (var i = 0; i < strips; i++) {
      final u0 = width * i / strips, u1 = width * (i + 1) / strips;
      final angle = p * math.pi + lift * .12 * (i / strips - .5);
      final normal = math.cos(angle);
      final positions = normal >= 0 ? frontPositions : backPositions;
      final uv = normal >= 0 ? frontUV : backUV;
      final indices = normal >= 0 ? frontIndices : backIndices;
      final normals = normal >= 0 ? frontNormals : backNormals;
      final path = normal >= 0 ? frontPath : backPath;
      double x(double u) => u * math.cos(p * math.pi);
      double skew(double u) =>
          math.sin(p * math.pi) * (touchY.clamp(0.0, 1.0) - .5) * u * .08;
      final points = [
        Offset(x(u0), skew(u0)),
        Offset(x(u1), skew(u1)),
        Offset(x(u1), height + skew(u1)),
        Offset(x(u0), height + skew(u0)),
      ];
      final offset = positions.length ~/ 2;
      for (final point in points) {
        positions.addAll([point.dx, point.dy]);
        normals.add(normal);
      }
      uv.addAll([u0, 0, u1, 0, u1, height, u0, height]);
      indices.addAll([
        offset,
        offset + 1,
        offset + 2,
        offset,
        offset + 2,
        offset + 3,
      ]);
      path.addPolygon(points, true);
    }
    ReaderPaperMesh mesh(
      List<double> positions,
      List<double> uv,
      List<int> indices,
      List<double> normals,
      Path path,
    ) => ReaderPaperMesh(
      positions: Float32List.fromList(positions),
      uv: Float32List.fromList(uv),
      indices: Uint16List.fromList(indices),
      normals: normals,
      outline: path,
    );
    front = mesh(
      frontPositions,
      frontUV,
      frontIndices,
      frontNormals,
      frontPath,
    );
    back = mesh(backPositions, backUV, backIndices, backNormals, backPath);
    frontInk = front;
    backInk = back;
    sheet = Path.combine(PathOperation.union, front.outline, back.outline);
  }
  final Size size;
  final double gap;
  late final double lift;
  late final ReaderPaperMesh front, back, frontInk, backInk;
  late final Path sheet;
}
