<?php
$config["request_path"] = "/mail/";

// IMAP/SMTP with TLS but skip cert verification (internal Docker network)
$config["imap_host"] = "tls://dovecot-mailcow:143";
$config["smtp_host"] = "tls://postfix-mailcow:587";
$config["imap_conn_options"] = [
  "ssl" => [
    "verify_peer" => false,
    "verify_peer_name" => false,
  ]
];
$config["smtp_conn_options"] = [
  "ssl" => [
    "verify_peer" => false,
    "verify_peer_name" => false,
  ]
];

// Branding
$config["product_name"] = "NovaFrame Mail";
$config["support_url"] = "https://www.novaframe.cloud";
// No custom logo — use default Roundcube logo

// Enable custom theme plugin
$config["plugins"] = array_filter(array_unique(array_merge(
  $config["plugins"] ?? [],
  ["archive", "zipdownload", "managesieve", "password", "markasjunk", "novaframe_theme"]
)));

// UI tweaks
$config["layout"] = "widescreen";
$config["preview_pane"] = true;
$config["refresh_interval"] = 60;
$config["message_show_email"] = true;
$config["html_editor"] = 1;
$config["draft_autosave"] = 60;
