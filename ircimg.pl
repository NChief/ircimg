############################################################################################
# ircimg v1.0 by NChief
# This scripts saves every image linkend in channels and saves them to a directory.
#
# IrssiX::Async is needed (used for forking the download to avoid blocking)
# you can get it at http://mauke.dyndns.org/stuff/irssi/lib/IrssiX/
# You also need WWW::Mechanize and DBI (get it from cpan)
#
## Settings:
# /set ircimg_path /var/www/ircimg
#	Where to save the images. (usualy where your web-server get files)
# /set ircimg_url http://yoursite.com/ircimg
#	The url where the images wil be located throug www
# /set ircimg_ircnet EFNet
#	When a new image arives it get announce on a channel, what ircnet is that channel on.
# /set ircimg_channel #myircimgs
#	Announce channel.
# /set ircimg_channelexcludelist #chan1 #chan2
#	space sepreated list of channels you DONT want to get images from.
# /set ircimg_channellist #chan1 #chan2
#	space sepreted list of channels you WANT to get images from. ALL channels if empty.
############################################################################################

use strict;
use Irssi qw(print settings_add_str settings_get_str settings_add_bool settings_get_bool);
use warnings;
use vars qw($VERSION %IRSSI);
use WWW::Mechanize;
use DBI;
use Digest::MD5 qw(md5_hex);
use IrssiX::Async qw(fork_off);

# IRSSI
$VERSION = "1.0";
%IRSSI = (
        authours => 'NChief',
        contact => 'NChief @ EFNet',
        name => 'ircimg',
        description => 'Saves all images to a folder.'
);

my $ok = 0;
my $mech = WWW::Mechanize->new(autocheck => 0);
$mech->agent_alias( 'Windows Mozilla' );

settings_add_str('ircimg', 'ircimg_path', '/var/www/ircimg');
settings_add_str('ircimg', 'ircimg_url', 'http://yoursite.net/ircimg');
settings_add_str('ircimg', 'ircimg_ircnet', 'EFNet');
settings_add_str('ircimg', 'ircimg_channel', '#myircimgs');
settings_add_str('ircimg', 'ircimg_channelexcludelist', ''); # space seperated list with channels you want to exclude
settings_add_str('ircimg', 'ircimg_channellist', ''); # space sepreated list. wil only get images from channels in list. All channels if empty
settings_add_bool('ircimg', 'ircimg_debug', 0);

sub fork_dl {
	my ($url, $channel, $nick) = @_;
	my $debug = settings_get_bool('ircimg_debug');
	my $link = settings_get_str('ircimg_url');
	return 1 if ($url =~ /\Q$link\E/);
	fork_off('', sub { $mech->get($url); $mech->success ? print $mech->content : print undef; }, sub {
		my ($content) = shift;
	
		unless (defined $content) {
			print CRAP "\002ircimg debug:\002 no content" if $debug;
			return;
		}
		
		my $md5 = md5_hex($content);
	
		my $dbfile = Irssi::get_irssi_dir()."/imgmd5.sqlite";
		
		my $dbh = DBI->connect( "dbi:SQLite:$dbfile" ) || die "Cannot connect: $DBI::errstr";
		my $res = $dbh->selectall_arrayref( "SELECT md5 FROM imgmd5 WHERE md5=".$dbh->quote($md5)." LIMIT 1" );
		if($#{$res} eq 0) { # already downloaded
			print CRAP "\002ircimg debug:\002 $url already downloaded: $md5" if $debug;
			#print $content if ($url =~ /4chan/);
			return;
		}
		unless ($dbh->do("INSERT INTO imgmd5 (md5) VALUES (".$dbh->quote($md5).")")) {
			print CRAP "\002ircimg debug:\002 $url error inserting md5 to db" if $debug;
			return;
		}
		
		$url =~ /.*\/(.*)/;
		my $name = $1;
		$name =~ s/\%20/_/g;
		$name =~ s/\%2B/-/g;
		$name = URLDecode($name);
		while(-e '/var/www/ircimg/'.$name) {
			$name = "1".$name;
		}
		my $path = settings_get_str('ircimg_path');
		$path =~ s/\/$//;
		if(open(my $IMG, ">", $path.'/'.$name)) {
			binmode $IMG;
			print $IMG $content;
			close($IMG);
		} else {
			print CRAP "\002ircimg debug:\002 err opening file: $!" if $debug;
			return;
		}
		unless (-B $path.'/'.$name) {
			unlink($path.'/'.$name);
			print CRAP "\002ircimg debug:\002 $url not a binary file" if $debug;
			return 1;
		}
		
		$link =~ s/\/$//;
		my $ircnet = settings_get_str('ircimg_ircnet');
		my $a_channel = settings_get_str('ircimg_channel');
		print CRAP "\002ircimg:\002 ".$link."/".$name." on \002".$channel."\002 by \002".$nick."\002" if ($link);
		Irssi::server_find_tag($ircnet)->command("msg ".$a_channel." \002ircimg:\002 ".$link."/".$name." on \002".$channel."\002 by \002".$nick."\002") if ($a_channel && $ircnet && $link);
		print CRAP "\002ircimg:\002 ".$path."/".$name." on \002".$channel."\002 by \002".$nick."\002" unless ($link);
		return 1;
	}
	);
}

sub check {
	my($msg, $target, $nick) = @_;
	if (settings_get_str('ircimg_channelexcludelist')) {
		my @excludes = split(/\s/, settings_get_str('ircimg_channelexcludelist'));
		return if (grep(/^$target$/, @excludes));
	}
	if (settings_get_str('ircimg_channellist')) {
		my @channels = split(/\s/, settings_get_str('ircimg_channellist'));
		return unless (grep(/^$target$/, @channels));
	}
	while($msg =~ /(http\S+\.(jpg|png|gif|jpeg))/g) {
		fork_dl($1, $target, $nick) if $ok;
	}
	while($msg =~ /http:\/\/imgur\.com\S*\/(\S+)/g) {
		my $id = $1;
		next if ($id =~ /\.(jpg|png|gif|jpeg)$/);
		fork_dl('http://i.imgur.com/'.$id.'.jpg', $target, $nick) if $ok;
	}
	while($msg =~ /(http:\/\/artige\.no\/bilde\/\d+)/g) {
		$mech->get($1);
		if ($mech->success && $mech->content =~ /<img src="(\S+)" alt="artig bilde"/ && $ok) {
			fork_dl($1, $target, $nick);
		}
	}
	while($msg =~ /http:\/\/bildr\.no\/view\/(\d+)/g) {
		fork_dl('http://bildr.no/image/'.$1.'.jpeg', $target, $nick) if $ok;
	}
	while($msg =~ /(http:\/\/cl\.ly\/\S+)/g) {
		$mech->get($1);
		if ($mech->success && $mech->content =~ /src="(http:\/\/cl\.ly\S+)"/ && $ok) {
			fork_dl($1, $target, $nick);
		}
	}
	while($msg =~ /(http:\/\/www\.imagebam\.com\/image\/\S+)/g) {
		$mech->get($1);
		if ($mech->success && $mech->content =~ /src="(http:\/\/\d+\S+)"/ && $ok) {
			fork_dl($1, $target, $nick);
		}
	}
	while($msg =~ /http:\/\/apina\.biz\/(\d+)/g) {
		apina($1, $target, $nick) if $ok;
	}
	while($msg =~ /http:\/\/apinaporn\.com\/(\d+)/g) {
		apina($1, $target, $nick) if $ok;
	}
}

sub event_public_message {
	my ($server, $msg, $nick, $address, $target) = @_;
	if ($msg =~ /http/) {
		check($msg, $target, $nick);
	}
}

sub own_text {
	my ($server, $msg, $channel) = @_;
	if ($msg =~ /http/) {
		check($msg, $channel, $server->{nick});
	}
}

#apina.biz and apinaporn.com
sub apina {
	my ($id, $channel, $nick) = @_;
	my @exts = ('jpg', 'JPG', 'gif', 'jpeg');
	foreach my $ext (@exts) {
		fork_dl('http://fi4.eu.apcdn.com/full/'.$id.'.'.$ext, $channel, $nick);
	}
}

sub create_db {
	my $dbfile = Irssi::get_irssi_dir()."/imgmd5.sqlite";
	my $dbh = DBI->connect( "dbi:SQLite:$dbfile" ) || die "Cannot connect: $DBI::errstr";
	if($dbh->do("CREATE TABLE imgmd5 ( id INTEGER PRIMARY KEY, md5 TEXT )")) {
		$ok = 1;
		print CRAP "DB created";
	} else {
		print CLIENTERROR "Error creating db, try again with /ircimg_db";
		print CLIENTERROR $! if ($!);
	}
}

sub URLDecode {
	my $theURL = $_[0];
	$theURL =~ tr/+/ /;
	$theURL =~ s/%([a-fA-F0-9]{2,2})/chr(hex($1))/eg;
	$theURL =~ s/<!--(.|\n)*-->//g;
	return $theURL;
}

if (-e Irssi::get_irssi_dir()."/imgmd5.sqlite") {
	$ok = 1;
} else {
	create_db()
}

Irssi::signal_add("message public", "event_public_message");
Irssi::signal_add('message own_public', 'own_text');
Irssi::command_bind("ircimg_db", "create_db");