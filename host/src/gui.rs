// Fenêtre native (egui/eframe — pas de HTML) : assistant de configuration au premier lancement, puis
// tableau de bord (joueurs connectés, démarrer/arrêter, expulser, réglages, mises à jour).
//
// GUI = thread principal, synchrone (egui est "immediate mode" : update() est rappelée en boucle). Le
// relais WebSocket (relay.rs) tourne sur un runtime tokio séparé (voir main.rs) ; les boutons qui ont besoin
// d'await (Démarrer) passent par rt.block_on(...), bref et sans conséquence ici (juste le temps de lier le
// port). Les appels Supabase (reqwest::blocking) sont de simples appels synchrones directs.
use std::sync::mpsc::{channel, Receiver};
use std::sync::Arc;

use eframe::egui;
use uuid::Uuid;

use crate::config::{self, Config};
use crate::logger::log;
use crate::relay::{self, ServerState};
use crate::supabase;
use crate::updater::{self, LatestRelease};

const GREEN: egui::Color32 = egui::Color32::from_rgb(74, 222, 128);
const RED: egui::Color32 = egui::Color32::from_rgb(255, 107, 107);
const ORANGE: egui::Color32 = egui::Color32::from_rgb(255, 102, 0);

pub struct HostApp {
    state: Arc<ServerState>,
    rt: tokio::runtime::Handle,
    host_id: Uuid,
    configured: bool,

    form_name: String,
    form_has_password: bool,
    form_password: String,
    form_port: String,

    status_msg: String,
    error_msg: String,
    busy: bool,

    update_rx: Receiver<Option<LatestRelease>>,
    update_available: Option<LatestRelease>,
    update_in_progress: bool,
    update_error: String,
}

impl HostApp {
    pub fn new(state: Arc<ServerState>, rt: tokio::runtime::Handle, host_id: Uuid, cfg: Config, configured: bool, current_tag: String) -> Self {
        let (tx, update_rx) = channel();
        std::thread::spawn(move || {
            let result = updater::check_latest(&current_tag);
            let _ = tx.send(result);
        });
        HostApp {
            state,
            rt,
            host_id,
            configured,
            form_name: cfg.name,
            form_has_password: cfg.password.is_some(),
            form_password: cfg.password.unwrap_or_default(),
            form_port: cfg.port.to_string(),
            status_msg: String::new(),
            error_msg: String::new(),
            busy: false,
            update_rx,
            update_available: None,
            update_in_progress: false,
            update_error: String::new(),
        }
    }

    fn submit_setup(&mut self) {
        self.error_msg.clear();
        let cfg = match self.form_to_config() {
            Ok(c) => c,
            Err(e) => { self.error_msg = e; return; }
        };
        self.busy = true;
        match supabase::save_config(self.host_id, &cfg) {
            Ok(_) => {
                config::cache_save(&cfg);
                self.state.set_config(cfg);
                if let Err(e) = self.rt.block_on(relay::start(self.state.clone())) {
                    log(&format!("Démarrage du relais impossible : {}.", e));
                }
                self.configured = true;
                self.status_msg = "Configuration enregistrée, serveur démarré.".into();
            }
            Err(e) => self.error_msg = format!("Enregistrement impossible (Supabase) : {}", e),
        }
        self.busy = false;
    }

    fn save_settings(&mut self) {
        self.error_msg.clear();
        let cfg = match self.form_to_config() {
            Ok(c) => c,
            Err(e) => { self.error_msg = e; return; }
        };
        self.busy = true;
        match supabase::save_config(self.host_id, &cfg) {
            Ok(_) => {
                config::cache_save(&cfg);
                let running = self.state.is_running();
                self.state.set_config(cfg);
                self.status_msg = if running {
                    "Enregistré. Cliquez Arrêter puis Démarrer pour appliquer (port / mot de passe).".into()
                } else {
                    "Enregistré.".into()
                };
            }
            Err(e) => self.error_msg = format!("Enregistrement impossible (Supabase) : {}", e),
        }
        self.busy = false;
    }

    fn form_to_config(&self) -> Result<Config, String> {
        let port: u16 = self.form_port.trim().parse().map_err(|_| "Port invalide (nombre entre 1 et 65535 attendu).".to_string())?;
        if port == 0 { return Err("Port invalide.".into()); }
        let name = if self.form_name.trim().is_empty() { Config::default().name } else { self.form_name.trim().to_string() };
        let password = if self.form_has_password && !self.form_password.trim().is_empty() { Some(self.form_password.trim().to_string()) } else { None };
        Ok(Config { name, password, port })
    }

    fn start_update(&mut self) {
        if let Some(rel) = self.update_available.clone() {
            self.update_in_progress = true;
            self.update_error.clear();
            // Bloquant : court téléchargement, et en cas de succès le processus se relance et sort de lui-même.
            if let Err(e) = updater::download_and_install(&rel.download_url) {
                self.update_error = e;
                self.update_in_progress = false;
            }
        }
    }
}

impl eframe::App for HostApp {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        if let Ok(result) = self.update_rx.try_recv() {
            self.update_available = result;
        }

        egui::CentralPanel::default().show(ctx, |ui| {
            if !self.configured {
                self.ui_setup(ui);
            } else {
                self.ui_dashboard(ui);
            }
        });

        // Rafraîchit la liste des joueurs / le statut même sans interaction.
        ctx.request_repaint_after(std::time::Duration::from_secs(1));
    }
}

impl HostApp {
    fn ui_setup(&mut self, ui: &mut egui::Ui) {
        ui.heading("GRNFR Host CMP — premier lancement");
        ui.label("Configurez votre serveur. Tout est modifiable ensuite depuis cette fenêtre.");
        ui.add_space(12.0);

        ui.label("Nom du serveur");
        ui.text_edit_singleline(&mut self.form_name);
        ui.add_space(6.0);
        ui.checkbox(&mut self.form_has_password, "Protéger par un mot de passe");
        if self.form_has_password {
            ui.label("Mot de passe");
            ui.add(egui::TextEdit::singleline(&mut self.form_password).password(true));
        }
        ui.add_space(6.0);
        ui.label("Port d'écoute (WebSocket) — valeur par défaut : 30814");
        ui.text_edit_singleline(&mut self.form_port);
        ui.add_space(14.0);

        if !self.error_msg.is_empty() {
            ui.colored_label(RED, self.error_msg.as_str());
        }
        ui.add_enabled_ui(!self.busy, |ui| {
            if ui.button(if self.busy { "Enregistrement…" } else { "Enregistrer et démarrer" }).clicked() {
                self.submit_setup();
            }
        });
    }

    fn ui_dashboard(&mut self, ui: &mut egui::Ui) {
        ui.heading("GRNFR Host CMP");
        ui.add_space(4.0);

        let cfg = self.state.config();
        let running = self.state.is_running();
        ui.horizontal(|ui| {
            if running {
                ui.colored_label(GREEN, "🟢 En ligne");
            } else {
                ui.colored_label(RED, "🔴 Arrêté");
            }
            ui.label(format!("{} · port {}{}", cfg.name, cfg.port, if cfg.password.is_some() { " · protégé" } else { "" }));
            if running {
                if ui.button("Arrêter le serveur").clicked() {
                    relay::stop(&self.state);
                }
            } else if ui.button("Démarrer le serveur").clicked() {
                if let Err(e) = self.rt.block_on(relay::start(self.state.clone())) {
                    self.error_msg = format!("Démarrage impossible : {}", e);
                }
            }
        });
        if !self.status_msg.is_empty() {
            ui.colored_label(GREEN, self.status_msg.as_str());
        }
        if !self.error_msg.is_empty() {
            ui.colored_label(RED, self.error_msg.as_str());
        }

        if let Some(rel) = self.update_available.clone() {
            ui.add_space(8.0);
            egui::Frame::group(ui.style()).fill(egui::Color32::from_rgb(40, 28, 10)).show(ui, |ui| {
                ui.horizontal(|ui| {
                    ui.colored_label(ORANGE, format!("Nouvelle version disponible : {}", rel.tag));
                    ui.add_enabled_ui(!self.update_in_progress, |ui| {
                        if ui.button(if self.update_in_progress { "Installation…" } else { "Télécharger et installer" }).clicked() {
                            self.start_update();
                        }
                    });
                });
                if !self.update_error.is_empty() {
                    ui.colored_label(RED, self.update_error.as_str());
                }
            });
        }

        ui.add_space(10.0);
        ui.separator();
        let players = self.state.players();
        ui.heading(format!("Joueurs connectés ({})", players.len()));
        if players.is_empty() {
            ui.weak("Personne pour le moment.");
        }
        egui::ScrollArea::vertical().max_height(220.0).show(ui, |ui| {
            for p in &players {
                ui.horizontal(|ui| {
                    ui.label(p.username.as_str());
                    ui.weak(p.peer.as_str());
                    ui.weak(format!("{}s", p.joined_secs));
                    if ui.button("Expulser").clicked() {
                        self.state.kick(p.id);
                    }
                });
            }
        });

        ui.add_space(10.0);
        ui.separator();
        egui::CollapsingHeader::new("Paramètres du serveur").show(ui, |ui| {
            ui.label("Nom du serveur");
            ui.text_edit_singleline(&mut self.form_name);
            ui.checkbox(&mut self.form_has_password, "Protéger par un mot de passe");
            if self.form_has_password {
                ui.label("Mot de passe");
                ui.add(egui::TextEdit::singleline(&mut self.form_password).password(true));
            }
            ui.label("Port d'écoute (WebSocket)");
            ui.text_edit_singleline(&mut self.form_port);
            ui.add_space(6.0);
            ui.add_enabled_ui(!self.busy, |ui| {
                if ui.button("Enregistrer").clicked() {
                    self.save_settings();
                }
            });
            ui.weak("Sans mot de passe, n'importe qui connaissant votre adresse peut rejoindre. Un changement de port ou de mot de passe n'est repris qu'au prochain démarrage (Arrêter puis Démarrer ci-dessus).");
        });
    }
}
