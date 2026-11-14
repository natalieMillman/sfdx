trigger LogEventTrigger on Log_Event__e(after insert) {
  LogEventHandler.handle(Trigger.new);
}
