class_name MwAudioPump
extends Node
## What is heard on its own clock (owner, 2026-10-13: the music dropped out
## after goals). The heard driver of an online client's split sound
## ([method MwRouter.split_audio]: it answers nothing the game asks) is not
## stepped by its router's ticks: a client's game holds a tick while the
## host's stream is late (a goal's screen changes cost the host a frame or
## two), a screen's entry holds the main thread, and the sound card's
## [constant MwAudio.BUFFER_TARGET] (70 ms) ran dry. This pump runs the
## driver's ticks the wall clock says are due instead - on a thread of its
## own ([member threaded]), so neither a held tick nor a busy main thread
## starves the sound card. The game's calls reach the driver under its lock
## ([method MwAudio.lock]: [MwHeard], a resync), which the thread holds for
## each look.
##
## Only what is heard keeps this clock: the game's own driver (a model, or
## the one driver offline and on the host) is stepped by the game's ticks,
## so every answer the game reads stays the original's (the frame-rate
## guard, test_frame_rate.gd, allows this file for that reason).

## Pumped on a thread of its own; off (`--no-audio-thread`): on the main
## thread each rendered frame (the driver's node in the tree).
static var threaded := true
## The thread's rest between its looks at the clock (microseconds).
const SLEEP_USEC := 4000
## The most ticks one look runs: a longer wait (the pump itself held, a
## breakpoint) is let go - the clock starts again from there.
const MAX_TICKS := 30

## The driver pumped.
var audio: MwAudio
var _thread: Thread = null
var _go := false
## The clock's start (Time.get_ticks_usec) and the ticks run since.
var _t0 := 0
var _ticks := 0


static func _static_init() -> void:
	if "--no-audio-thread" in OS.get_cmdline_user_args():
		threaded = false


func _init(audio_: MwAudio = null) -> void:
	audio = audio_
	name = "Pump"


## The clock starts now; on a thread of its own ([param use_thread]) or,
## inside the tree, each rendered frame.
func start(use_thread := threaded) -> void:
	_t0 = Time.get_ticks_usec()
	_ticks = 0
	if use_thread:
		_go = true
		_thread = Thread.new()
		_thread.start(_loop, Thread.PRIORITY_HIGH)
	set_process(not use_thread)


## Stops (the thread finished first).
func stop() -> void:
	if _thread != null:
		audio.lock()
		_go = false
		audio.unlock()
		_thread.wait_to_finish()
		_thread = null
	set_process(false)


## Whether it runs on a thread of its own.
func on_thread() -> bool:
	return _thread != null


## The clock's start (Time.get_ticks_usec).
func started_at() -> int:
	return _t0


## The ticks due by the wall clock at [param now_usec] (since [method
## start]), run on the driver; returns how many ([constant MAX_TICKS] at
## most: a longer wait is let go). The caller holds the driver's lock (or
## no other thread can call).
func pump(now_usec: int) -> int:
	var due := int((now_usec - _t0) * MwAudio.TICKS_PER_SECOND / 1000000.0) - _ticks
	if due > MAX_TICKS:
		_ticks += due - MAX_TICKS
		due = MAX_TICKS
	for i in maxi(due, 0):
		audio.tick()
		_ticks += 1
	return maxi(due, 0)


func _loop() -> void:
	while true:
		audio.lock()
		if not _go:
			audio.unlock()
			return
		pump(Time.get_ticks_usec())
		audio.unlock()
		OS.delay_usec(SLEEP_USEC)


func _process(_delta: float) -> void:
	if _thread == null and audio != null:
		pump(Time.get_ticks_usec())
