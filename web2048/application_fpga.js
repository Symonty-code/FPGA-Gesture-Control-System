// Replacement for the original js/application.js when FPGA control is enabled.
// It keeps the original GameManager but exposes the instance so the FPGA
// gesture extension can control it.
window.requestAnimationFrame(function () {
  window.gameManager = new GameManager(
    4,
    KeyboardInputManager,
    HTMLActuator,
    LocalStorageManager
  );

  window.fpga2048 = new Fpga2048Controller(window.gameManager);
});
