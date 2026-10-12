abstract interface class Clock {
  DateTime get now;
  int get utcOffsetMinutes;
}

final class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime get now => DateTime.now();

  @override
  int get utcOffsetMinutes => now.timeZoneOffset.inMinutes;
}
