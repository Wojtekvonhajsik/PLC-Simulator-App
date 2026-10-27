import 'dart:math';

import 'data_types.dart';
import 'ladder.dart';

/// State of an IEC timer instance. Values are updated only when the timer box
/// is executed (as on S7-1200), not when its members are read.
final class TimerState {
  TimerState(this.kind);

  final TimerKind kind;

  bool _input = false;
  bool _q = false;
  int _et = 0;
  int _pt = 0;
  bool _timing = false;
  int _start = 0;
  int _accumulated = 0;

  bool get input => _input;
  bool get q => _q;

  /// Elapsed time in ms.
  int get et => _et;

  /// Preset time in ms, copied from the PT input on each call.
  int get pt => _pt;

  void update({required bool input, required int preset, required int now, bool reset = false}) {
    final pt = max(0, preset);
    _pt = pt;
    switch (kind) {
      case TimerKind.ton:
        if (!input) {
          _timing = false;
          _et = 0;
          _q = false;
        } else {
          if (!_timing) {
            _timing = true;
            _start = now;
          }
          _et = min(now - _start, pt);
          _q = _et >= pt;
        }
      case TimerKind.tof:
        if (input) {
          _timing = false;
          _et = 0;
          _q = true;
        } else if (_q) {
          if (!_timing) {
            _timing = true;
            _start = now;
          }
          _et = min(now - _start, pt);
          if (_et >= pt) {
            _timing = false;
            _q = false;
          }
        }
      case TimerKind.tp:
        if (!_timing && input && !_input) {
          _timing = true;
          _start = now;
        }
        if (_timing) {
          _et = min(now - _start, pt);
          if (_et >= pt) _timing = false;
        } else if (!input) {
          _et = 0;
        }
        _q = _timing;
      case TimerKind.tonr:
        if (reset) {
          _timing = false;
          _accumulated = 0;
          _et = 0;
        } else if (input) {
          if (!_timing) {
            _timing = true;
            _start = now;
          }
          _et = min(_accumulated + now - _start, pt);
        } else if (_timing) {
          _timing = false;
          _accumulated = _et;
        }
        _q = !reset && _et >= pt && (pt > 0 || input);
    }
    _input = input;
  }
}

/// State of an IEC counter instance (INT range).
final class CounterState {
  CounterState(this.kind);

  final CounterKind kind;

  int _cv = 0;
  int _pv = 0;
  bool _cuPrevious = false;
  bool _cdPrevious = false;
  bool _qu = false;
  bool _qd = false;

  int get cv => _cv;
  int get pv => _pv;
  bool get qu => _qu;
  bool get qd => _qd;

  /// Q of CTU (CV >= PV) or CTD (CV <= 0).
  bool get q => kind == CounterKind.ctd ? _qd : _qu;

  void update({
    required int preset,
    bool countUp = false,
    bool countDown = false,
    bool reset = false,
    bool load = false,
  }) {
    _pv = preset;
    final up = countUp && !_cuPrevious;
    final down = countDown && !_cdPrevious;
    _cuPrevious = countUp;
    _cdPrevious = countDown;
    if (reset) {
      _cv = 0;
    } else if (load) {
      _cv = preset;
    } else {
      if (up && _cv < intMax) _cv++;
      if (down && _cv > intMin) _cv--;
    }
    _qu = _cv >= _pv;
    _qd = _cv <= 0;
  }
}
