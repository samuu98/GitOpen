import 'package:gitopen/application/workspaces/repository_validator.dart';

final class PassThroughRepositoryValidator implements RepositoryValidator {
  const PassThroughRepositoryValidator();

  @override
  Future<String> validate(String path) async => path;
}
