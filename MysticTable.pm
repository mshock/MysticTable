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
my $x = new CGI::Ajax( 'paginate' => \&paginate );

my $page = $q->param('page');
warn $page;


if (defined $page) {
	print paginate($page);
}
else {
	print "HTTP/1.0 200 OK\r\n";
	print $x->build_html( $q, \&main );
}


sub main {
	
	return
	$q->start_html(
		
			-title=>'SchedMon',
			-bgcolor=>"#cccccc",
			-script=>
			[
			{
				-type => 'text/javascript',
				-src=> 'magic_table.js' 
			},
			{
				-type => 'text/javascript',
				-src => 'http://www.google.com/jsapi'
			},
			{
				-type => 'text/javascript',
				-code => gen_script()
			}
			]
		
	).
	$q->div({-id=>'chart_div'}).
	$q->div({-id=>'pop_div'}).
	$q->end_html;
}

sub gen_script {
	
	
	
	my @date_range = gen_range();
	my $num_cols = scalar @date_range;
	my $add_cols = "data.addColumn('string','feed');\n";
	for my $date (@date_range) {
		$add_cols .= "data.addColumn('number','$date');\n";
	}
	
	my $feeds_aref = $dbh_sched->selectall_arrayref( "
    	select distinct top 19 u.name, u.update_id 
    	from tqasched.dbo.updates u, tqasched.dbo.update_schedule us
    	where
    	u.update_id = us.update_id
    	and us.enabled = 1
    	order by update_id asc  
    " );
    my $num_rows = scalar @$feeds_aref;
    my $set_cells = '';
    my $row = 0;
    for my $feed_aref (@$feeds_aref) {
    	my ($name, $id) = @$feed_aref;
    	$set_cells .= "data.setCell($row,0,'$name');\n";
    	my $col = 1;
    	for my $date (@date_range) {
    		my ($val) = $dbh_sched->selectrow_array( "
    			select str(cast(hist_epoch - sched_epoch as float) / 3600, 4, 2)  from update_history u, update_schedule s where
				feed_date = '$date' and u.update_id = $id and u.update_id = s.update_id and s.sched_id = u.sched_id
    		" );
    		$val = 'null' unless defined $val;
    		$set_cells .= "data.setCell($row,$col,$val);\n";
    		$col++;	
    	}
    	$row++;
    }
	
	
	my $draw_vis = <<SCRIPT;
    google.load("visualization", "1");
    google.setOnLoadCallback(drawVisualization);
	
    function drawVisualization()
    {
      var rows = $num_rows;
      var columns = $num_cols;
      var data = new google.visualization.DataTable();
      $add_cols
      data.addRows(rows);

      $set_cells

      var vis = new greg.ross.visualisation.MagicTable(document.getElementById('chart_div'));

      options = {};
      options.tableTitle = "SchedMon";
      options.enableFisheye = false;
      options.enableBarFill = false;
      options.pageSize = 19;
      options.defaultRowHeight = 25;
      options.columnWidths = [{column : 0, width : 300}];
      options.defaultColumnWidth = 60;
      options.rowHeaderCount = 1;
      options.columnHeaderCount = 0;
      options.tablePositionX = 50;
      options.tablePositionY = 50;
      options.tableHeight = 492;
      options.tableWidth = 1000;
      options.colourRamp = getColourRamp();

      vis.draw(data, options);
  }
  
  function getColourRamp()
  {
      var colour1 = {red:0, green:0, blue:255};
      var colour2 = {red:0, green:255, blue:255};
      var colour3 = {red:0, green:255, blue:0};
      var colour4 = {red:255, green:255, blue:0};
      var colour5 = {red:255, green:0, blue:0};
      return [colour1, colour2, colour3, colour4, colour5];
  }
SCRIPT

	return $draw_vis;
}

sub paginate {
	my $page = shift;
	my $page_start = $page * 20 + 1;
	my $page_end = $page_start + 19;
	my @date_range = gen_range();
	my $feeds_aref = $dbh_sched->selectall_arrayref("
	select  rownum, name, update_id 
	from (
		select row_number() over (order by update_id) as rownum, name, update_id
		from tqasched.dbo.updates
    	where
    	enabled = 1
    ) as rowconstrainedresult
	where rownum >= $page_start
	and rownum < $page_end
	order by rownum");
	
	# build multidimensional array AJAX return string
	my ($row, $col) = (0,0);
	my @cells;
	for my $feed_aref (@$feeds_aref) {
    	my ($rownum, $name, $id) = @$feed_aref;
    	push @cells, "[$row,0,\"$name\"]";
    	my $col = 1;
    	for my $date (@date_range) {
    		my ($val) = $dbh_sched->selectrow_array( "
    			select str(cast(hist_epoch - sched_epoch as float) / 3600, 4, 2)  from update_history u, update_schedule s where
				feed_date = '$date' and u.update_id = $id and u.update_id = s.update_id and s.sched_id = u.sched_id
    		" );
    		$val = 'null' unless defined $val;
    		push @cells, "[$row,$col,$val]";
    		$col++;	
    	}
    	$row++;
    }
    return '[[' . join(',',@date_range) . '],[' .  join(',',@cells) . ']]';	
}


sub gen_range {
	my $time = time;
	my @range;
	for ( -20 .. -1 ) {
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