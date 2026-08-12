# FPGA Gesture 2048 Web Integration

This directory contains the browser-side extension for connecting the Nexys A7 gesture controller to the original open-source 2048 web game.

## FPGA command protocol

The FPGA sends one ASCII byte per validated gesture at 115200 baud:

- `L` = tilt left
- `R` = tilt right
- `U` = tilt forward
- `D` = tilt backward
- `T` = tap
- `S` = shake
- `F` = flip

## State-dependent game mapping

### Home
- `T` = Play / Resume

### Gameplay
- `L` = Move left
- `R` = Move right
- `U` = Move up
- `D` = Move down
- `T` = Undo immediately previous valid move
- `S` = Home
- `F` = Open restart confirmation

### Restart confirmation
- `L` = YES, restart/new game
- `R` = NO, return to the same game

## Integration with original 2048

Start from the original `gabrielecirulli/2048` source. Keep its core game files unchanged.

Copy these files into its `js/` directory:

- `fpga_game_extension.js`
- `fpga_serial_controller.js`
- `application_fpga.js`

Then, in `index.html`, after `js/game_manager.js`, load the FPGA extension and replace the original application bootstrap:

```html
<script src="js/game_manager.js"></script>
<script src="js/fpga_game_extension.js"></script>
<script src="js/application_fpga.js"></script>
<script src="js/fpga_serial_controller.js"></script>
```

Do not also load the original `js/application.js` when using `application_fpga.js`.

## Browser connection

The page exposes a **Connect FPGA** button. In a supported desktop browser, click it and select the Nexys A7 USB-UART serial port. The browser opens the port at 115200 baud and consumes `L/R/U/D/T/S/F` bytes directly.

For Web Serial, serve the game from a secure context such as localhost during development rather than opening `index.html` directly from the filesystem.

## Design principle

The original 2048 movement/merge/score/game-over algorithm remains the application logic. Gesture acquisition, filtering, recognition, debouncing, one-shot command generation, and UART transmission remain on the FPGA. The browser extension only translates the validated FPGA command into the appropriate state-dependent 2048 action.
