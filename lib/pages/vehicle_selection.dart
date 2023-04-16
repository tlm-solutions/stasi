import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:background_location/background_location.dart';
import 'package:provider/provider.dart';

import 'package:stasi/notifiers/running_recording.dart';
import 'package:stasi/db/database_bloc.dart';


class _IntegerTextField extends StatefulWidget {
  const _IntegerTextField({
    required this.fieldName,
    required this.onChanged,
    Key? key,
  }) : super(key: key);

  final String fieldName;
  final ValueChanged<int?> onChanged;

  @override
  State<StatefulWidget> createState() => _IntegerTextFieldState();
}

class _IntegerTextFieldState extends State<_IntegerTextField> {

  @override
  Widget build(BuildContext context) => TextFormField(
    decoration: InputDecoration(labelText: widget.fieldName),
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    onChanged: (String value) {
        widget.onChanged(value.isNotEmpty ? int.parse(value) : null);
    },
    validator: (value) => value != null && value.isNotEmpty ? null : 'Enter the ${widget.fieldName}',
  );

}

class VehicleSelection extends StatefulWidget {
  final DatabaseBloc databaseBloc;

  const VehicleSelection({Key? key, required this.databaseBloc}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _VehicleSelectionState();
}

class _VehicleSelectionState extends State<VehicleSelection> with AutomaticKeepAliveClientMixin<VehicleSelection> {
  int? lineNumber;
  int? runNumber;
  int regionId = 0;

  final _dropdownFormKey = GlobalKey<FormState>();
  Timer? _debounce;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Consumer<RunningRecording>(
      builder: (context, recording, child) {
        final started = recording.recordingId != null;

        return Form(
          key: _dropdownFormKey,
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _IntegerTextField(
                    fieldName: "line number",
                    onChanged: (int? lineNumber) {
                      setState(() {
                        this.lineNumber = lineNumber;
                      });

                      if (!started) return;

                      _scheduleUpdateRecording(recording.recordingId!);
                    },
                  ),
                  _IntegerTextField(
                    fieldName: 'run number',
                    onChanged: (int? runNumber) {
                      setState(() {
                        this.runNumber = runNumber;
                      });

                      if (!started) return;

                      _scheduleUpdateRecording(recording.recordingId!);
                    },
                  ),
                  DropdownButton<int>(
                    value: regionId,
                    alignment: AlignmentDirectional.bottomEnd,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(
                        value: 0,
                        child: Center(child: Text("Dresden")),
                      ),
                      DropdownMenuItem(
                        value: 1,
                        child: Center(child: Text("Chemnitz")),
                      ),
                    ],
                    onChanged: (newRegion) {
                      setState(() {
                        regionId = newRegion ?? 0;
                      });

                      if (!started) return;

                      _scheduleUpdateRecording(recording.recordingId!);
                    },
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      if (started) {
                        BackgroundLocation.stopLocationService();
                        _killDebounce();
                        await widget.databaseBloc.cleanRecording(recording.recordingId!);
                        recording.setRecordingId(null);
                        return;
                      }

                      final recordingId = await widget.databaseBloc.createRecording(
                        runNumber: runNumber,
                        lineNumber: lineNumber,
                        regionId: regionId,
                      );

                      recording.setRecordingId(recordingId);

                      BackgroundLocation.setAndroidNotification(
                        title: "Stasi",
                        message: "Stasi is watching you!",
                        icon: "@mipmap/ic_launcher",
                      );
                      BackgroundLocation.setAndroidConfiguration(1200);
                      BackgroundLocation.startLocationService();

                      BackgroundLocation.getLocationUpdates((location) async {
                        /*
                         * This skips the location values while the
                         * gps chip is still calibrating.
                         * Haven't tested this on IOS yet.
                         */
                        const minimumAccuracy = 62;
                        if (location.accuracy! > minimumAccuracy) {
                          debugPrint("Too inaccurate location: ${location.accuracy!} (> $minimumAccuracy)");
                          return;
                        }

                        await widget.databaseBloc.createCoordinate(recordingId,
                          latitude: location.latitude!,
                          longitude: location.longitude!,
                          altitude: location.altitude!,
                          speed: location.speed!,
                        );
                      });
                    },
                    child: started ? const Text("LEAVING VEHICLE") : const Text("ENTERING VEHICLE"),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

  }

  @override
  bool get wantKeepAlive => true;

  void _killDebounce() {
    if (_debounce?.isActive ?? false) _debounce?.cancel();
  }

  void _scheduleUpdateRecording(int recordingId) {
    _killDebounce();
    _debounce = Timer(const Duration(seconds: 1), () async {
      _updateRecording(recordingId);
    });
  }

  Future<void> _updateRecording(int recordingId) async {
    await widget.databaseBloc.setRecordingRunAndLineNumber(
      recordingId,
      runNumber: runNumber,
      lineNumber: lineNumber,
    );

    await widget.databaseBloc.setRecordingRegionId(recordingId, regionId);
  }
}
