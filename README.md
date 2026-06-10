to add commands:
  go to local commands = {};

  to add a new command, call
    command.new {
      name: string,
      callback: (...any) -> any,
      isClientLocked: boolean,
    }
