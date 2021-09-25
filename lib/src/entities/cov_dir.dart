import 'dart:io';

import 'package:collection/collection.dart';
import 'package:coverde/src/entities/cov_base.dart';
import 'package:coverde/src/entities/cov_file.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// {@template cov_dir}
/// # Covered Directory
///
/// A [CovElement] that holds coverage data about a [source] directory.
///
/// The data includes coverage [elements] that encapsulates coverage data about
/// all filesystem entities within the [source] folder.
/// {@endtemplate}
@immutable
class CovDir extends CovElement {
  /// Create a [CovDir] instance.
  ///
  /// {@macro cov_dir}
  @visibleForTesting
  CovDir({
    required this.source,
    required Iterable<CovElement> elements,
  }) : _elements = elements;

  /// Create a coverage data tree structure that replicates the [source]
  /// organization in the filesystem.
  factory CovDir.tree({
    required Iterable<CovFile> covFiles,
  }) =>
      subtree(
        baseDirPath: null,
        coveredFiles: covFiles,
      );

  /// Create a coverage data tree structure that replicates filesystem tree
  /// organization with the given [coveredFiles] and [baseDirPath].
  @visibleForTesting
  static CovDir subtree({
    required String? baseDirPath,
    required Iterable<CovFile> coveredFiles,
  }) {
    // Filter files directly or indirectly within this directory.
    final covFiles = baseDirPath == null
        ? coveredFiles
        : coveredFiles.where(
            (covFile) => p.isWithin(
              baseDirPath,
              covFile.source.path,
            ),
          );

    // If no covered files within this folder, return the covered directory.
    if (covFiles.isEmpty) {
      stdout.writeln('No covered files in the <$baseDirPath> folder.');
      return CovDir(
        source: Directory(baseDirPath ?? ''),
        elements: const [],
      );
    }

    // Folders directly or indirectly within this directory.
    final dirPaths =
        covFiles.map((covFile) => covFile.source.parent.path).toSet();

    // Get folders segments.
    final dirsSegments = dirPaths.map(p.split).toList();

    // Pick path with fewest number of segments.
    final fewestSegments = minBy<Iterable<String>, int>(
      dirsSegments,
      (dirSegments) => dirSegments.length,
    )!;

    final commonSegments =
        baseDirPath == null ? <String>[] : p.split(baseDirPath);
    late final Iterable<String> nextSegments;

    {
      var segmentIdx = commonSegments.length;

      bool shortestPathChecked() => segmentIdx >= fewestSegments.length;

      Iterable<String> nextSegmentsGroup() => dirsSegments
          .where((s) => s.length > segmentIdx)
          .map((s) => s[segmentIdx])
          .toSet();

      while (!shortestPathChecked() && nextSegmentsGroup().length <= 1) {
        commonSegments.addAll(nextSegmentsGroup());
        segmentIdx++;
      }

      nextSegments = nextSegmentsGroup();
    }

    // Build actual base path.
    final actualBasePath = commonSegments.reduce(p.join);

    // Build nested folders data from next segments.
    final allDirs = nextSegments.map(
      (nextSegment) => subtree(
        baseDirPath: p.join(actualBasePath, nextSegment),
        coveredFiles: covFiles,
      ),
    );
    final validDirs = allDirs.where((dir) => dir.linesFound > 0);

    final files = covFiles.where(
      (covFile) => p.equals(covFile.source.parent.path, actualBasePath),
    );

    return CovDir(
      source: Directory(actualBasePath),
      elements: [
        ...validDirs,
        ...files,
      ],
    );
  }

  @override
  final Directory source;

  final Iterable<CovElement> _elements;

  /// The organized coverage data about the filesystem entities within the
  /// [source] folder.
  late final UnmodifiableListView<CovElement> elements =
      UnmodifiableListView(_elements);

  @override
  late final linesFound = _elements.map((e) => e.linesFound).sum;

  @override
  late final linesHit = _elements.map((e) => e.linesHit).sum;

  static const _equality = IterableEquality<CovElement>();

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is CovDir &&
        p.equals(other.source.path, source.path) &&
        _equality.equals(other._elements, _elements);
  }

  @override
  int get hashCode =>
      p.canonicalize(source.path).hashCode ^ _equality.hash(_elements);

  @override
  String toString() {
    final buf = StringBuffer(
      'Node: ${source.path} ($coverage% - $linesHit/$linesFound)',
    );
    elements.map(
      (e) {
        if (e is CovFile) {
          final path = e.source.path;
          final cov = e.coverage.toStringAsFixed(2);
          final linesHit = e.linesHit;
          final linesFound = e.linesFound;
          return '\n├─ SF: $path ($cov% - $linesHit/$linesFound)';
        } else if (e is CovDir) {
          return '\n├─ ${e.toString().replaceAll('\n', '\n│  ')}';
        }
      },
    ).forEach(buf.write);
    buf.writeln();
    return buf.toString();
  }
}