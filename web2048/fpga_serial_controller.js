(function () {
  "use strict";

  var port = null;
  var reader = null;
  var keepReading = false;

  var connectButton;
  var statusLabel;

  function buildSerialUi() {
    var box = document.createElement("div");
    box.style.position = "fixed";
    box.style.right = "10px";
    box.style.bottom = "10px";
    box.style.zIndex = "10002";
    box.style.background = "#bbada0";
    box.style.padding = "8px";
    box.style.borderRadius = "5px";
    box.style.fontFamily = "Arial, sans-serif";

    connectButton = document.createElement("button");
    connectButton.textContent = "Connect FPGA";
    connectButton.style.cursor = "pointer";
    connectButton.style.padding = "7px 10px";

    statusLabel = document.createElement("span");
    statusLabel.textContent = " Disconnected";
    statusLabel.style.color = "white";
    statusLabel.style.marginLeft = "6px";

    box.appendChild(connectButton);
    box.appendChild(statusLabel);
    document.body.appendChild(box);

    connectButton.addEventListener("click", connectFpga);
  }

  function setStatus(text) {
    if (statusLabel) statusLabel.textContent = " " + text;
  }

  async function connectFpga() {
    if (!("serial" in navigator)) {
      setStatus("Web Serial not supported in this browser");
      return;
    }

    try {
      port = await navigator.serial.requestPort();
      await port.open({ baudRate: 115200 });

      setStatus("Connected @ 115200");
      connectButton.disabled = true;
      keepReading = true;
      readLoop();
    } catch (error) {
      setStatus("Connection failed");
      console.error("FPGA serial connection error:", error);
    }
  }

  async function readLoop() {
    var decoder = new TextDecoder();

    while (port && port.readable && keepReading) {
      reader = port.readable.getReader();

      try {
        while (true) {
          var result = await reader.read();
          if (result.done) break;
          if (!result.value) continue;

          var text = decoder.decode(result.value, { stream: true });
          for (var i = 0; i < text.length; i++) {
            var command = text.charAt(i).toUpperCase();

            if ("LRUDTSF".indexOf(command) !== -1) {
              if (window.fpga2048) {
                window.fpga2048.handleGesture(command);
              }
            }
          }
        }
      } catch (error) {
        console.error("FPGA serial read error:", error);
        setStatus("Serial read stopped");
      } finally {
        reader.releaseLock();
        reader = null;
      }
    }
  }

  window.addEventListener("load", buildSerialUi);
})();
