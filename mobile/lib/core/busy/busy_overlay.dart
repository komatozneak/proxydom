import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Phases for the shell-level busy blocker.
enum BusyPhase { idle, working, success, failed }

/// Immutable UI state for [BusyOverlayHost].
class BusyOverlayState {
  const BusyOverlayState({
    this.phase = BusyPhase.idle,
    this.title,
    this.body,
  });

  final BusyPhase phase;
  final String? title;
  final String? body;

  bool get isBusy => phase != BusyPhase.idle;

  BusyOverlayState copyWith({
    BusyPhase? phase,
    String? title,
    String? body,
    bool clearBody = false,
  }) {
    return BusyOverlayState(
      phase: phase ?? this.phase,
      title: title ?? this.title,
      body: clearBody ? null : (body ?? this.body),
    );
  }
}

/// Shell-level busy overlay controller. Screens call [run]; host stays mounted.
class BusyOverlayNotifier extends Notifier<BusyOverlayState> {
  @override
  BusyOverlayState build() => const BusyOverlayState();

  bool get isBusy => state.isBusy;

  Future<T> run<T>(
    Future<T> Function() action, {
    required String workingTitle,
    String? workingBody,
    String? successTitle,
    String? failedTitle,
    Duration successHold = const Duration(milliseconds: 700),
    Duration failedHold = const Duration(milliseconds: 900),
  }) async {
    if (state.isBusy) {
      throw StateError('busy overlay already active');
    }
    state = BusyOverlayState(
      phase: BusyPhase.working,
      title: workingTitle,
      body: workingBody,
    );
    try {
      final result = await action();
      state = BusyOverlayState(
        phase: BusyPhase.success,
        title: successTitle ?? workingTitle,
      );
      await Future<void>.delayed(successHold);
      await _clearIdle();
      return result;
    } catch (e) {
      state = BusyOverlayState(
        phase: BusyPhase.failed,
        title: failedTitle ?? workingTitle,
      );
      await Future<void>.delayed(failedHold);
      await _clearIdle();
      rethrow;
    }
  }

  Future<void> _clearIdle() async {
    final done = Completer<void>();
    void finish() {
      state = const BusyOverlayState();
      if (!done.isCompleted) done.complete();
    }

    final binding = SchedulerBinding.instance;
    binding.addPostFrameCallback((_) => finish());
    binding.scheduleFrame();
    // Fallback when no frame is pumped (unit tests without tester.pump).
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 32), () {
        if (!done.isCompleted) finish();
      }),
    );
    await done.future;
  }
}

final busyOverlayProvider =
    NotifierProvider<BusyOverlayNotifier, BusyOverlayState>(
  BusyOverlayNotifier.new,
);
