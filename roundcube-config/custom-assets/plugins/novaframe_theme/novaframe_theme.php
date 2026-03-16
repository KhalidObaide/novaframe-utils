<?php
class novaframe_theme extends rcube_plugin
{
    public function init()
    {
        $this->add_hook("render_page", array($this, "inject_assets"));
    }

    public function inject_assets($args)
    {
        $css_file = "/var/www/html/custom-assets/novaframe.css";
        if (file_exists($css_file)) {
            $css = "<style>\n" . file_get_contents($css_file) . "\n</style>";
            $args["content"] = str_replace("</head>", $css . "\n</head>", $args["content"]);
        }

        $logo_file = "/var/www/html/custom-assets/logo.svg";
        if (file_exists($logo_file)) {
            $logo_data = "data:image/svg+xml;base64," . base64_encode(file_get_contents($logo_file));
            $pattern = chr(47) . "src=" . chr(34) . "[^" . chr(34) . "]*logo" . chr(92) . ".svg[^" . chr(34) . "]*" . chr(34) . chr(47);
            $replacement = "src=" . chr(34) . $logo_data . chr(34);
            $args["content"] = preg_replace($pattern, $replacement, $args["content"]);
        }

        return $args;
    }
}
