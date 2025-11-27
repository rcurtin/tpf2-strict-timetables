### Strict Timetables

This is a mod for Transport Fever 2 that aims to improve upon the excellent work
of @IncredibleHannes, @Gregory365, and others who worked on the
[Timetables mod](https://github.com/Gregory365/TPF2-Timetables).

In essence the goal of the effort is to provide a better interface for strict
timetables: in the original Timetables mod, a vehicle would be assigned to a
departure time slot whenever it arrived at a station.  However, you can get some
really bad problems when trains are late, because they will end up in the
departure time slot that was actually intended for the *next* train, and this
can cause all kinds of havoc on mainlines.

Therefore the timetabling strategy here is *strict*:

 * At the beginning of a line, a vehicle is assigned to a time slot for
   departure from the first station.

 * This time slot is specific to the entire route: so, e.g., if the first timed
   departure from the first station is set at 00:00, and the first timed
   departure from the second station is set at 11:00, a vehicle that gets the
   00:00 departure from the first station will be assigned to the 11:00 first
   departure from the second station (and the first departure time slot from all
   subsequent stations).

 * If a vehicle arrives after its scheduled departure time, it will leave
   immediately in an attempt to make up for lost time.

Note that there are *no arrival times* in this mod; you only set the departure
times at each stop.  Therefore, you might want to consider adding enough "slack"
in the schedule to account for delays between stations (or just make sure that
delays don't happen!).
