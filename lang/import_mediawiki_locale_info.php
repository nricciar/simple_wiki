<?php
  function get_ns_names_for($name,$namespaceNames,$namespaceAliases)
  {
    $ret = $namespaceNames[$name];
    foreach($namespaceAliases as $key => $value) {
      if ($value == $name)
        $ret .= ",".$key;
    }
    return $ret;
  }
  if (!file_exists("mwsource")) {
    mkdir("mwsource");
  }
  if (!file_exists("mwsource/messages")) {
    system("svn co http://svn.wikimedia.org/svnroot/mediawiki/branches/REL1_18/phase3/languages/messages/ mwsource/messages");
  }
  error_reporting(E_ERROR);
  if ($handle = opendir('mwsource/messages/')) {
    while (false !== ($entry = readdir($handle))) {
      if (preg_match("/^Messages([\w]+).php$/", $entry, $matches) > 0) {
        include "mwsource/messages/".$entry;

        $cur_lang = strtolower($matches[1]);
        $doc = '';
        $doc .= ":".strtolower($matches[1]).":\n";
        $doc .= "  table of contents: \"" . addslashes($messages['toc']) . "\"\n";
        $doc .= "  edit: \"" . addslashes($messages['edit']) . "\"\n";
        $doc .= "  edit tab: \"" . addslashes($messages['edit']) . "\"\n";
        $doc .= "  edit section: \"" . addslashes(str_replace("$1","%{name}",$messages['editsectionhint'])) . "\"\n";
        $doc .= "  editing page: \"" . addslashes(str_replace("$1","%{name}",$messages['editing'])) . "\"\n";
        $doc .= "  summary: \"" . addslashes($messages['summary']) . "\"\n";
        $doc .= "  update: \"" . addslashes($messages['savearticle']) . "\"\n";
        $doc .= "  preview: \"" . addslashes($messages['preview']) . "\"\n";
        $doc .= "  revision history: \"" . addslashes(str_replace("$1","%{name}",$messages['history-title'])) . "\"\n";
        $doc .= "  history tab: \"" . addslashes($messages['history_short']) . "\"\n";
        $doc .= "  compare revisions: \"" . addslashes($messages['compare-selector']) . "\"\n";
        $doc .= "  pages in category: \"" . addslashes(str_replace("$1","%{category}",$messages['category_header'])) . "\"\n\n";
        $doc .= "  namespaces:\n";
        $doc .= "    media: \"" . get_ns_names_for(NS_MEDIA,$namespaceNames,$namespaceAliases) . "\"\n";
        $doc .= "    file: \"" . get_ns_names_for(NS_FILE,$namespaceNames,$namespaceAliases) . "\"\n";
        $doc .= "    category: \"" . get_ns_names_for(NS_CATEGORY,$namespaceNames,$namespaceAliases) . "\"\n";
        $doc .= "    template: \"" . get_ns_names_for(NS_TEMPLATE,$namespaceNames,$namespaceAliases) . "\"\n";
        $doc .= "    special: \"" . get_ns_names_for(NS_SPECIAL,$namespaceNames,$namespaceAliases) . "\"\n";
        $doc .= "    help: \"" . get_ns_names_for(NS_HELP,$namespaceNames,$namespaceAliases) . "\"\n";
        $doc .= "    talk: \"" . get_ns_names_for(NS_TALK,$namespaceNames,$namespaceAliases) . "\"\n\n";

        if ($cur_lang != "en") {
          file_put_contents($cur_lang.".yml",$doc);
          echo "created ".$cur_lang.".yml\n";
        }
      }
    }
  }
?>
