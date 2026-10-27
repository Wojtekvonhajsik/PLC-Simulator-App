/// Couples the PLC runtime with the plant simulation.
///
/// Re-exports `plc_core` and `plant_core`, so the app needs a single import.
library;

export 'package:plant_core/plant_core.dart';
export 'package:plc_core/plc_core.dart';

export 'src/clock.dart';
export 'src/io_binding.dart';
export 'src/simulation.dart';
