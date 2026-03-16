<?php
class novaframe_theme extends rcube_plugin
{
    public function init()
    {
        $this->add_hook("render_page", array($this, "inject_css"));
    }

    public function inject_css($args)
    {
        $css_file = "/var/www/html/custom-assets/novaframe.css";
        if (file_exists($css_file)) {
            $css = "<style>\n" . file_get_contents($css_file) . "\n</style>";
            $args["content"] = str_replace("</head>", $css . "\n</head>", $args["content"]);
        }

        // Replace logo src
        $args["content"] = str_replace(
            "src=\"skins/elastic/images/logo.svg\"",
            "src=\"data:image/svg+xml;base64," . base64_encode(file_get_contents("/var/www/html/custom-assets/logo.svg")) . "\"",
            $args["content"]
        );

        return $args;
    }
}
