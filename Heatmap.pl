#! perl -w

use strict;
use CGI;
use CGI::Ajax;
use DBI;
use Config::Simple;


#print join "\n", gen_range() and exit;

my $cfg = new Config::Simple('dbs.conf');

my $sched_db = $cfg->param( -block => 'SCHED' );
my $dbh_sched = init_handle($sched_db);


my $q = new CGI;
#my $x = new CGI::Ajax( 'ajax_func' => \&perl_func );
my $html = main();
#my $html = $x->build_html( $q, \&main );
print "HTTP/1.0 200 OK\r\n$html";

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
		$q->div( { -id => 'heatmapContainer' } ),
		$q->end_html();
	return $html;
}

sub heatmap_ajax {
	my $heatmap = "google.setOnLoadCallback(drawHeatMap);
      function drawHeatMap() {
          var data = new google.visualization.DataTable();";

	$heatmap .= "\ndata.addColumn('string','Feed Name');";

	# add columns for the adjacent days
	my @date_range = gen_range();
	for (@date_range) {
		$heatmap .= "\ndata.addColumn('number','$_');";
	}

	my $feeds_aref = $dbh_sched->selectall_arrayref( "
    	select name, update_id from tqasched.dbo.updates
    " );

	# add row for each feed
	my $num_rows = scalar @$feeds_aref;
	$heatmap .= "data.addRows($num_rows);";

	my ( $col, $row ) = (0,0);
	for my $feed_aref (@$feeds_aref) {
		my ( $name, $id ) = @$feed_aref;
		$heatmap .= "\ndata.setCell($row,$col,'$name');";
		$col++;
		for my $date (@date_range) {
			my ($val) = $dbh_sched->selectrow_array( "
    			select (cast(hist_epoch - sched_epoch as float)) / 3600 from update_history u, update_schedule s where
				feed_date = '$date' and u.update_id = $id and u.update_id = s.update_id and s.sched_id = u.sched_id
    		" );
    		next unless (defined $val);
    		if ($val >= 7) {
    			$val = 7;
    		}
    		elsif ($val <= -7){
    			$val = -7
    		}
    		$heatmap .= "\ndata.setCell($row,$col,$val);";
			$col++;
		}
		$col = 0;
		$row++;
	}
	$heatmap
		.= "heatmap = new org.systemsbiology.visualization.BioHeatMap(document.getElementById('heatmapContainer'));
          heatmap.draw(data, {});
      }";
	return $heatmap;
}

sub gen_range {
	my $time = time;
	my @range;
	for ( -3 .. -1 ) {
		my $ntime = $time + $_ * 86400;
		my ( $sec, $min, $hour, $mday, $mon, $y, $wday, $yday, $isdst )
			= gmtime($ntime);
		push @range, sprintf( "%u%02u%02u", $y + 1900, $mon + 1, $mday );
	}

	return @range;
}


sub init_handle {
	my $db = shift;

	# connecting to master since database may need to be created
	return
		DBI->connect(
		sprintf(
			"dbi:ODBC:Driver={SQL Server};Database=%s;Server=%s;UID=%s;PWD=%s",
			$db->{name}, $db->{server}, $db->{user}, $db->{pwd},
		)
		) or die "failed to initialize database handle\n", $DBI::errstr;
}
