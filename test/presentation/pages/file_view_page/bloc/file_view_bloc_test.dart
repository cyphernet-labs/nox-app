import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/model/chat/message_attachment.dart';
import 'package:nox_app/domain/model/file/file_type.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/file/file_repository.dart';
import 'package:nox_app/presentation/pages/file_view_page/bloc/file_view_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'file_view_bloc_test.mocks.dart';

/// Contract §2.1 draws a line here that is easy to erase by accident: bytes
/// that are gone are TERMINAL on this screen with no retry, while a connection
/// failure keeps its retry. Collapsing the two would tell people a file is lost
/// forever every time their train enters a tunnel.
@GenerateMocks([FileRepository])
void main() {
  late MockFileRepository files;

  const attachment = MessageAttachment(id: 'f1', type: FileType.pdf, name: 'spec.pdf', sizeBytes: 1024);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await configureDependencies(Environment.test);
    provideDummy<RepositoryResult<String>>(RepositoryResult.error(exception: RepositoryException.unknown));
    files = MockFileRepository();
    when(files.localPathFor(fileId: anyNamed('fileId'), suggestedName: anyNamed('suggestedName'))).thenAnswer((_) async => null);
    getIt.allowReassignment = true;
    getIt.registerSingleton<FileRepository>(files);
  });

  tearDown(() async => getIt.reset());

  void answerDownload(RepositoryResult<String> result) {
    when(
      files.download(fileId: anyNamed('fileId'), suggestedName: anyNamed('suggestedName'), onProgress: anyNamed('onProgress')),
    ).thenAnswer((_) async => result);
  }

  blocTest<FileViewBloc, FileViewState>(
    'bytes that are gone end the screen — terminal, and never downloading again',
    setUp: () => answerDownload(RepositoryResult<String>.error(exception: RepositoryException.attachmentGone)),
    build: () => FileViewBloc(file: attachment),
    act: (bloc) => bloc.add(const FileViewEvent.started()),
    wait: const Duration(milliseconds: 200),
    verify: (bloc) => expect(bloc.state.status, FileViewStatus.gone),
  );

  blocTest<FileViewBloc, FileViewState>(
    'a file the server never heard of is terminal too',
    setUp: () => answerDownload(RepositoryResult<String>.error(exception: RepositoryException.notFound)),
    build: () => FileViewBloc(file: attachment),
    act: (bloc) => bloc.add(const FileViewEvent.started()),
    wait: const Duration(milliseconds: 200),
    verify: (bloc) => expect(bloc.state.status, FileViewStatus.gone),
  );

  blocTest<FileViewBloc, FileViewState>(
    'a lost connection is NOT terminal — the retry has to stay available',
    setUp: () => answerDownload(RepositoryResult<String>.error(exception: RepositoryException.connection)),
    build: () => FileViewBloc(file: attachment),
    act: (bloc) => bloc.add(const FileViewEvent.started()),
    wait: const Duration(milliseconds: 200),
    verify: (bloc) {
      expect(bloc.state.status, FileViewStatus.failed);
      expect(bloc.state.status, isNot(FileViewStatus.gone), reason: 'a tunnel is not a deleted file');
    },
  );

  blocTest<FileViewBloc, FileViewState>(
    'a successful fetch makes Save possible',
    setUp: () => answerDownload(const RepositoryResult<String>.success(data: '/tmp/f1.pdf')),
    build: () => FileViewBloc(file: attachment),
    act: (bloc) => bloc.add(const FileViewEvent.started()),
    wait: const Duration(milliseconds: 200),
    verify: (bloc) {
      expect(bloc.state.status, FileViewStatus.ready);
      expect(bloc.state.canSave, isTrue);
      expect(bloc.state.file.localPath, '/tmp/f1.pdf');
    },
  );

  blocTest<FileViewBloc, FileViewState>(
    'a stored path that no longer resolves is not believed',
    // iOS rewrites the app-container path on every update, so a path saved
    // months ago routinely points at nothing. Trusting it would leave the
    // screen claiming to be ready over a file that is not there.
    setUp: () => answerDownload(const RepositoryResult<String>.success(data: '/tmp/refetched.pdf')),
    build: () => FileViewBloc(file: attachment.copyWith(localPath: '/nope/gone.pdf')),
    act: (bloc) => bloc.add(const FileViewEvent.started()),
    wait: const Duration(milliseconds: 200),
    verify: (bloc) {
      expect(bloc.state.file.localPath, '/tmp/refetched.pdf', reason: 'it fetched instead of trusting the stale path');
    },
  );

  blocTest<FileViewBloc, FileViewState>(
    'a file already on this device is not fetched again',
    setUp: () {
      File('${Directory.systemTemp.path}/nox_here.pdf').writeAsBytesSync([1]);
      answerDownload(RepositoryResult<String>.error(exception: RepositoryException.unknown));
    },
    build: () => FileViewBloc(file: attachment.copyWith(localPath: '${Directory.systemTemp.path}/nox_here.pdf')),
    act: (bloc) => bloc.add(const FileViewEvent.started()),
    wait: const Duration(milliseconds: 200),
    verify: (bloc) {
      expect(bloc.state.status, FileViewStatus.ready);
      verifyNever(files.download(fileId: anyNamed('fileId'), suggestedName: anyNamed('suggestedName'), onProgress: anyNamed('onProgress')));
    },
  );
}
