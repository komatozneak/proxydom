/// Result тип для обработки успешных/неуспешных операций без exceptions.
///
/// Используется в domain layer где хочется избежать try/catch в business logic.
/// UI слой может switch'ить на when() или valueOrNull.
sealed class Result<T> {
  const Result();

  R when<R>({
    required R Function(T value) success,
    required R Function(Object error, StackTrace? stackTrace) failure,
  }) {
    final self = this;
    return switch (self) {
      Success<T>(value: final v) => success(v),
      Failure<T>(error: final e, stackTrace: final st) => failure(e, st),
    };
  }

  bool get isSuccess => this is Success<T>;
  bool get isFailure => this is Failure<T>;

  T? get valueOrNull => switch (this) {
        Success<T>(value: final v) => v,
        Failure<T>() => null,
      };
}

class Success<T> extends Result<T> {
  const Success(this.value);
  final T value;
}

class Failure<T> extends Result<T> {
  const Failure(this.error, [this.stackTrace]);
  final Object error;
  final StackTrace? stackTrace;
}