// GRNFR Mod : application UI (AngularJS, système d'apps BeamNG).
angular.module('beamng.apps').directive('grnfrApp', ['bngApi', function (bngApi) {
  'use strict';
  // Seules ces clés/valeurs partent vers Lua (jamais de chaîne utilisateur libre).
  var SCHEMA = {
    hudEnabled: 'bool', showFps: 'bool', showAvg: 'bool',
    showMode: 'bool', showGraph: 'bool', compact: 'bool',
    refreshRate: [0, 1, 2, 4, 10], accent: ['orange', 'cyan', 'green', 'amber', 'violet'], opacity: 'num'
  };
  var HIST = 120;
  var STR = {
    fr: {
      tab_dashboard: 'Tableau de bord', tab_performance: 'Performance',tab_settings: 'Paramètres', tab_mods: 'Mods',
      open: 'HUD ouvert', closed: 'HUD fermé', unassigned: 'Touche non assignée', na: 'Non assignée', close: 'Fermer', openA: 'Ouvrir',
      avg: 'Moyenne 1 s', mode: 'Mode de jeu', hudState: 'État du HUD', on: 'Activé', off: 'Désactivé', notAvail: 'Non disponible',
      hudSettings: 'Paramètres du HUD', noMeasure: "Mesure indisponible (en attente d'images valides).",
      inst: 'FPS instantanés', avg2: 'Moyenne (1 s glissante)', hist: 'Historique', maxFps: 'FPS max', refresh: 'Rafraîchissement du HUD', refreshAuto: 'Auto (maximum)',
      perfNote: "Mesure : durée réelle des images rendues (moyenne = images / temps écoulé). 1 % low, frametime et usage GPU ne sont pas collectés.",
      source: 'source :', noData: 'Aucune donnée reçue.',
      hudEnabled: 'HUD activé', showFps: 'Afficher les FPS', showAvg: 'Afficher la moyenne 1 s',
      showMode: 'Afficher le mode de jeu',showGraph: 'Graphique de performance', compact: 'Mode compact',
      accent: 'Accent', opacity: 'Opacité', key: "Touche d'ouverture", keyNote: "Touche par défaut : K. Pour la changer : Options → Contrôles → « GRNFR CPM ».",
      reset: 'Restaurer les valeurs par défaut', dev: 'EN DÉVELOPPEMENT',
      mmText: "Fonctionnalité prévue : rechercher, examiner et installer des mods depuis des catalogues communautaires. Non disponible dans cette version : aucun téléchargement, aucune installation, aucune analyse de sécurité.",
      soon: 'Bientôt disponible',
      spec_cpu: 'Processeur', spec_gpu: 'Carte graphique', spec_ram: 'Mémoire RAM (totale)', spec_vram: 'Mémoire vidéo', spec_os: "Système d'exploitation", spec_resolution: 'Résolution du jeu', spec_gameVersion: 'Version du jeu',
      mode_garage: 'Garage', mode_bus: 'Bus', mode_rally: 'Rallye', mode_multiplayer: 'Multijoueur', mode_localmp: 'Multijoueur local', mode_startexp: 'Expérience de démarrage',
      mode_menu: 'Menu principal', mode_career: 'Carrière', mode_freeroam: 'Jeu libre', mode_scenario: 'Scénario', mode_session: 'Session active (mode inconnu)'
    },
    en: {
      tab_dashboard: 'Dashboard', tab_performance: 'Performance',tab_settings: 'Settings', tab_mods: 'Mods',
      open: 'HUD open', closed: 'HUD closed', unassigned: 'Key not assigned', na: 'Not assigned', close: 'Close', openA: 'Open',
      avg: '1 s average', mode: 'Game mode', hudState: 'HUD state', on: 'Enabled', off: 'Disabled', notAvail: 'Not available',
      hudSettings: 'HUD settings', noMeasure: 'Measurement unavailable (waiting for valid frames).',
      inst: 'Instant FPS', avg2: 'Average (rolling 1 s)', hist: 'History', maxFps: 'FPS max', refresh: 'HUD refresh rate', refreshAuto: 'Auto (maximum)',
      perfNote: 'Measurement: real duration of rendered frames (average = frames / elapsed time). 1% low, frametime and GPU usage are not collected.',
      source: 'source:', noData: 'No data received.',
      hudEnabled: 'HUD enabled', showFps: 'Show FPS', showAvg: 'Show 1 s average',
      showMode: 'Show game mode',showGraph: 'Performance graph', compact: 'Compact mode',
      accent: 'Accent', opacity: 'Opacity', key: 'Open key', keyNote: 'Default key: K. To change it: Options → Controls → "GRNFR CPM".',
      reset: 'Restore defaults', dev: 'IN DEVELOPMENT',
      mmText: 'Planned feature: search, review and install mods from community catalogs. Not available in this version: no download, no installation, no security scan.',
      soon: 'Coming soon',
      spec_cpu: 'Processor', spec_gpu: 'Graphics card', spec_ram: 'RAM (total)', spec_vram: 'Video memory', spec_os: 'Operating system', spec_resolution: 'Game resolution', spec_gameVersion: 'Game version',
      mode_garage: 'Garage', mode_bus: 'Bus', mode_rally: 'Rally', mode_multiplayer: 'Multiplayer', mode_localmp: 'Local multiplayer', mode_startexp: 'Starting experience',
      mode_menu: 'Main menu', mode_career: 'Career', mode_freeroam: 'Free roam', mode_scenario: 'Scenario', mode_session: 'Active session (unknown mode)'
    }
  };

  return {
    restrict: 'E', replace: true, scope: true,
    templateUrl: '/ui/modules/apps/GRNFR/app.html',
    link: function (scope) {
      scope.st = { session: false, hudOpen: false, version: '—', mode: '—', keyLabel: null, settings: null };
      scope.perf = { valid: false, fps: 0, avg: 0 };
      scope.tab = 'dashboard';
      scope.t = function (k) {
        var l = (scope.st.settings && scope.st.settings.lang) || 'fr';
        return (STR[l] && STR[l][k]) || STR.fr[k] || k;
      };
      scope.hudToggles = ['hudEnabled', 'showFps', 'showAvg', 'showMode', 'showGraph', 'compact'];
      scope.modeLabel = function () {
        var ids = scope.st.modeIds;
        if (ids && !Array.isArray(ids)) ids = Object.keys(ids).map(function (k) { return ids[k]; });
        if (!ids || !ids.length) return scope.st.mode;
        return ids.map(function (id) { var k = 'mode_' + id; return STR.fr[k] ? scope.t(k) : (scope.st.modeRaw || id); }).join(' · ');
      };
      scope.tabs = [
        { id: 'dashboard', label: 'Dashboard', icon: 'M3 3h8v8H3zM13 3h8v5h-8zM13 10h8v11h-8zM3 13h8v8H3z' },
        { id: 'performance', label: 'Performance', icon: 'M3 17l5-6 4 4 8-10' },
        { id: 'settings', label: 'Settings', icon: 'M4 7h10M18 7h2M4 17h2M10 17h10M14 4v6M6 14v6' },
        { id: 'mods', label: 'Mods', icon: 'M12 3l8 4v10l-8 4-8-4V7z' }
      ];
      scope.rates = SCHEMA.refreshRate;
      scope.rateLabel = function (r) { return r === 0 ? scope.t('refreshAuto') : r + ' Hz'; };
      scope.accents = SCHEMA.accent;
      var hist = [], lastHist = 0;
      scope.graphPoints = '';

      function applyScope(fn) {
        var p = scope.$root && scope.$root.$$phase;
        if (p === '$apply' || p === '$digest') fn(); else scope.$evalAsync(fn);
      }
      function lua(code) { bngApi.engineLua(code); }

      scope.setSetting = function (key, value) {
        var kind = SCHEMA[key];
        if (!kind) return;
        if (kind === 'bool') value = !!value;
        else if (kind === 'num') { value = Number(value); if (!isFinite(value)) return; }
        else if (kind.indexOf(value) < 0) return;
        if (scope.st.settings) scope.st.settings[key] = value; // retour visuel immédiat
        lua('extensions.grnfr.setSetting(' + JSON.stringify(key) + ',' + JSON.stringify(value) + ')');
      };
      scope.toggle = function (key) { scope.setSetting(key, !(scope.st.settings && scope.st.settings[key])); };
      scope.resetDefaults = function () { lua('extensions.grnfr.resetSettings()'); };
      scope.fmt = function (n) { return scope.perf.valid ? Math.round(n) : '—'; };

      function graphMax() {
        var st = scope.st.settings;
        var max = 30;
        for (var i = 0; i < hist.length; i++) if (hist[i] > max) max = hist[i];
        return Math.ceil(max / 10) * 10;
      }
      function yOf(v, max) { return 300 - (Math.min(Math.max(v / max, 0), 1) * 290 + 5); }
      function redrawGraph() {
        var max = graphMax(), off = HIST - hist.length, pts = [];
        for (var j = 0; j < hist.length; j++) pts.push((((off + j) / (HIST - 1)) * 1000).toFixed(1) + ',' + yOf(hist[j], max).toFixed(1));
        scope.graphPoints = pts.join(' ');
      }
      scope.hover = null;
      scope.graphLeave = function () { scope.hover = null; };
      scope.graphHover = function (e) {
        var n = hist.length;
        if (!n) { scope.hover = null; return; }
        var r = e.currentTarget.getBoundingClientRect(), off = HIST - n;
        var idx = Math.round(((e.clientX - r.left) / r.width) * (HIST - 1)) - off;
        if (idx < 0 || idx >= n) { scope.hover = null; return; }
        var v = hist[idx];
        scope.hover = { v: Math.round(v), x: ((off + idx) / (HIST - 1)) * 100, y: (yOf(v, graphMax()) / 300) * 100 };
      };

      // Secours : si Lua n'envoie aucune mesure pendant 1,5 s, on appelle extensions.grnfr.uiPoll() à chaque image.
      var lastTick = Date.now(), polling = false, pollDisabled = false, pollBusy = false, pollRaf = 0;
      function pollStep() {
        if (!polling) return;
        if (!pollBusy) {
          pollBusy = true;
          bngApi.engineLua('extensions.grnfr.uiPoll()', function (r) {
            pollBusy = false;
            if (r === 'hooks') { pollDisabled = true; polling = false; }
          });
        }
        if (polling) pollRaf = requestAnimationFrame(pollStep);
      }
      var pollTimer = setInterval(function () {
        if (!polling && !pollDisabled && !window.__grnfrPollOwner && Date.now() - lastTick > 1500) {
          window.__grnfrPollOwner = true; polling = true; pollStep();
        }
      }, 1000);
      function stopPoll() { if (polling) window.__grnfrPollOwner = false; polling = false; cancelAnimationFrame(pollRaf); }
      scope.$on('$destroy', function () { clearInterval(pollTimer); stopPoll(); });

      scope.$on('GRNFRTick', function (e, d) {
        if (!d) return;
        if (!d.poll) { lastTick = Date.now(); stopPoll(); }
        applyScope(function () {
          scope.perf.valid = !!d.valid;
          scope.perf.fps = Number(d.fps) || 0;
          scope.perf.avg = Number(d.avg) || 0;
          var now = Date.now();
          if (d.valid && now - lastHist >= 250) { lastHist = now; hist.push(scope.perf.avg); if (hist.length > HIST) hist.shift(); redrawGraph(); }
        });
      });
      scope.$on('GRNFRStatic', function (e, d) {
        if (!d) return;
        applyScope(function () {
          for (var k in d) if (Object.prototype.hasOwnProperty.call(d, k)) scope.st[k] = d[k];
          if (!d.session) { hist = []; scope.graphPoints = ''; scope.perf.valid = false; }
        });
      });
      scope.$on('$destroy', function () { lua('extensions.grnfr.uiClosed()'); });

      lua('extensions.grnfr.requestState()');
    }
  };
}]);
