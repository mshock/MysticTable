#! perl -w

package MysticTable;

use strict;
use CGI;
use CGI::Ajax;
use DBI;
use Config::Simple;
sub main {

	my $html = join "\n",
		$q->start_html(
		-title  => 'hello world',
		-script => [
			{  -type => 'text/javascript',
			   -src  => 'http://www.google.com/jsapi'
			},
			{  -type => 'text/javascript',
			   -code =>
				   ' google.load("visualization", "1", {});google.load("prototype", "1.6");'
			},
			{  -type => 'text/javascript',
			   -src =>
				   'http://systemsbiology-visualizations.googlecode.com/svn/trunk/src/main/js/load.js'
			},
			{  -type => 'text/javascript',
			   -code =>
				   'systemsbiology.load("visualization", "1.0", {packages:["bioheatmap"]});'
			},
			{  -type => 'text/javascript',
			   -code => heatmap_ajax()
			},
		]
		),
		$q->h1('Scheduling Heatmap'),
		$q->textfield( { -name    => 'val1',
						 -id      => 'val1',
						 -onkeyup => "ajax_func(['val1'],['resultdiv']);"
					   }
		),
		$q->div( { -id => 'resultdiv' } ),
		$q->div( { -id => 'heatmapContainer' } ),
		$q->end_html();
	return $html;
}
sub perl_func {
	my $input  = shift;
	my $output = $input . " was input!";
	return $output;
}