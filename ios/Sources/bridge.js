(() => {
  if (location.protocol !== "file:") return;
  const call = (data) => window.webkit.messageHandlers.bizzoo.postMessage(data);
  window.BizzooIOS = {
    enregistrerFichier: (name, base64, type) => call({ action: "share", name, base64, type }),
  };
  Object.defineProperty(navigator, "geolocation", { value: {
    getCurrentPosition: (success, failure) => {
      call({ action: "position" }).then(success).catch((error) => {
        if (failure) failure({ code: 1, message: String(error) });
      });
    },
  }, configurable: true });
})();
