(function () {
  "use strict";

  function cloneState(state) {
    return JSON.parse(JSON.stringify(state));
  }

  // Keep the original 2048 move algorithm intact, but remember the state
  // immediately before the most recent VALID move for one-step Undo.
  var originalMove = GameManager.prototype.move;

  GameManager.prototype.move = function (direction) {
    var before = cloneState(this.serialize());
    var beforeText = JSON.stringify(before);

    originalMove.call(this, direction);

    var afterText = JSON.stringify(this.serialize());
    if (beforeText !== afterText) {
      this.fpgaUndoState = before;
    }
  };

  GameManager.prototype.fpgaUndo = function () {
    if (!this.fpgaUndoState) return false;

    var state = cloneState(this.fpgaUndoState);

    this.grid = new Grid(state.grid.size, state.grid.cells);
    this.score = state.score;
    this.over = state.over;
    this.won = state.won;
    this.keepPlaying = state.keepPlaying;
    this.fpgaUndoState = null;

    this.actuate();
    return true;
  };

  function Fpga2048Controller(gameManager) {
    this.game = gameManager;
    this.mode = "HOME"; // HOME, GAME, RESTART_CONFIRM
    this.homeOverlay = null;
    this.restartOverlay = null;
    this.lastGestureLabel = null;

    this.buildUi();
    this.showHome();
  }

  Fpga2048Controller.prototype.buildUi = function () {
    var style = document.createElement("style");
    style.textContent =
      ".fpga-overlay{" +
      "position:fixed;inset:0;z-index:10000;display:flex;" +
      "align-items:center;justify-content:center;background:rgba(250,248,239,.94);" +
      "font-family:Arial,sans-serif;color:#776e65;text-align:center;}" +
      ".fpga-panel{background:#eee4da;padding:28px;border-radius:10px;" +
      "box-shadow:0 8px 28px rgba(0,0,0,.18);min-width:280px;}" +
      ".fpga-panel h2{margin:0 0 14px;font-size:30px;}" +
      ".fpga-panel p{margin:8px 0;font-size:16px;}" +
      ".fpga-choice{display:flex;justify-content:space-around;gap:20px;" +
      "font-weight:bold;font-size:22px;margin-top:20px;}" +
      ".fpga-chip{background:#8f7a66;color:white;border-radius:5px;padding:10px 18px;}" +
      ".fpga-status-line{position:fixed;left:10px;bottom:10px;z-index:10001;" +
      "background:#776e65;color:white;padding:8px 12px;border-radius:5px;" +
      "font-family:Arial,sans-serif;font-size:13px;}";
    document.head.appendChild(style);

    this.homeOverlay = document.createElement("div");
    this.homeOverlay.className = "fpga-overlay";
    this.homeOverlay.innerHTML =
      '<div class="fpga-panel">' +
      '<h2>FPGA Gesture 2048</h2>' +
      '<p>Tap the Nexys A7 to Play / Resume</p>' +
      '<p>Tilt: Left / Right / Forward / Backward</p>' +
      '<p>Tap in game: Undo &nbsp; | &nbsp; Shake: Home &nbsp; | &nbsp; Flip: Restart</p>' +
      '</div>';
    document.body.appendChild(this.homeOverlay);

    this.restartOverlay = document.createElement("div");
    this.restartOverlay.className = "fpga-overlay";
    this.restartOverlay.style.display = "none";
    this.restartOverlay.innerHTML =
      '<div class="fpga-panel">' +
      '<h2>Restart New Game?</h2>' +
      '<div class="fpga-choice">' +
      '<div class="fpga-chip">← Tilt Left: YES</div>' +
      '<div class="fpga-chip">Tilt Right: NO →</div>' +
      '</div></div>';
    document.body.appendChild(this.restartOverlay);

    this.lastGestureLabel = document.createElement("div");
    this.lastGestureLabel.className = "fpga-status-line";
    this.lastGestureLabel.textContent = "FPGA gesture: waiting";
    document.body.appendChild(this.lastGestureLabel);
  };

  Fpga2048Controller.prototype.showHome = function () {
    this.mode = "HOME";
    this.restartOverlay.style.display = "none";
    this.homeOverlay.style.display = "flex";
  };

  Fpga2048Controller.prototype.enterGame = function () {
    this.mode = "GAME";
    this.homeOverlay.style.display = "none";
    this.restartOverlay.style.display = "none";
  };

  Fpga2048Controller.prototype.openRestartConfirmation = function () {
    this.mode = "RESTART_CONFIRM";
    this.restartOverlay.style.display = "flex";
  };

  Fpga2048Controller.prototype.cancelRestart = function () {
    this.mode = "GAME";
    this.restartOverlay.style.display = "none";
  };

  Fpga2048Controller.prototype.confirmRestart = function () {
    this.game.fpgaUndoState = null;
    this.game.restart();
    this.mode = "GAME";
    this.restartOverlay.style.display = "none";
  };

  Fpga2048Controller.prototype.handleGesture = function (command) {
    if (!command) return;
    command = String(command).toUpperCase();

    if (this.lastGestureLabel) {
      this.lastGestureLabel.textContent = "FPGA gesture: " + command;
    }

    // HOME: only Tap starts/resumes the game.
    if (this.mode === "HOME") {
      if (command === "T") this.enterGame();
      return;
    }

    // RESTART_CONFIRM: left means YES, right means NO.
    if (this.mode === "RESTART_CONFIRM") {
      if (command === "L") this.confirmRestart();
      else if (command === "R") this.cancelRestart();
      return;
    }

    // GAMEPLAY mappings.
    switch (command) {
      case "U": this.game.move(0); break;
      case "R": this.game.move(1); break;
      case "D": this.game.move(2); break;
      case "L": this.game.move(3); break;
      case "T": this.game.fpgaUndo(); break;
      case "S": this.showHome(); break;
      case "F": this.openRestartConfirmation(); break;
      default: break;
    }
  };

  window.Fpga2048Controller = Fpga2048Controller;
})();
