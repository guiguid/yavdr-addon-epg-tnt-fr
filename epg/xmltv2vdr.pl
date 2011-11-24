#!/usr/bin/perl

# xmltv2vdr.pl
#
# Converts data from an xmltv output file to VDR - tested with 1.7
#
# The TCP SVDRSend and Receive functions have been used from the getskyepg.pl
# Plugin for VDR.
#
# This script requires: -
#
# The PERL module date::manip (required for xmltv anyway)
#
# You will also need xmltv installed to get the channel information:
# http://sourceforge.net/projects/xmltv
#
# This software is released under the GNU GPL
#
# See the README file for copyright information and how to reach the author.

# based on  $Id: xmltv2vdr.pl 1.0.7 2007/04/13 20:01:04 psr Exp $

# xmltv2vdr.pl adapted to :
# - automatic prosses http://xmltv.dyndns.org  tnt.xml file
# - handle multiple source from same channel with same egp info ( "TF1","TF1 HD" ...)
# by Guillaume DELVIT guiguid@free.fr - 24/11/2011

#use strict;
use Getopt::Std;
use Time::Local;
use Date::Manip;

my $sim=0;
my $verbose=0;
my $adjust;
my @xmllines;

# Translate HTML/XML encodings into normal characters
# For some German problems, and also English

sub xmltvtranslate
{
    my $line=shift;
    
    # German Requests - mail me with updates if some of these are wrong..
    
    $line=~s/ und uuml;/ü/g;
    $line=~s/ und auml;/ä/g; 
    $line=~s/ und ouml;/ö/g;
    $line=~s/ und quot;/"/g; 
    $line=~s/ und szlig;/ß/g; 
    $line=~s/ und amp;/\&/g; 
    $line=~s/ und middot;/·/g; 
    $line=~s/ und Ouml;/Ö/g; 
    $line=~s/ und Auml;/Ä/g;
    $line=~s/ und Uuml;/Ü/g ;
    $line=~s/ und eacute;/é/g;
    $line=~s/ und aacute;/á/g;
    $line=~s/ und deg;/°/g;
    $line=~s/ und ordm;/º/g;
    $line=~s/ und ecirc;/ê/g;
    $line=~s/ und ecirc;/ê/g;
    $line=~s/ und ccedil;/ç/g;
    $line=~s/ und curren;/€/g;
    $line=~s/und curren;/€/g;
    $line=~s/und Ccedil;/Ç/g;
    $line=~s/ und ocirc;/ô/g;
    $line=~s/ und egrave;/è/g;
    $line=~s/ und agrave;/à/g;
    $line=~s/und quot;/"/g;
    $line=~s/und Ouml;/Ö/g;
    $line=~s/und Uuml;/Ü/g;
    $line=~s/und Auml;/Ä/g;
    $line=~s/und ouml;/ö/g;
    $line=~s/und uuml;/ü/g;
    $line=~s/und auml;/ä/g;
    
    # English - only ever seen a problem with the Ampersand character..
    
    $line=~s/&amp;/&/g;

# English - found in Radio Times data

    $line=~s/&#8212;/--/g;
    $line=~s/&lt;BR \/&gt;/|/g;    

    return $line;
}

# Translate genre text to hex numbers 
sub genre_id {
	my ($xmlline, $genretxt, $genrenum) = @_;
	if ( $xmlline =~ m/\<category.*?\>($genretxt)\<\/category\>/)
	{
       	 return "G $genrenum\r\n";
	}
}
# Translate ratings text to hex numbers 
sub ratings_id {
	my ($xmlline, $ratingstxt, $ratingsnum) = @_;
	if ( $xmlline =~ m/\<value\>($ratingstxt)\<\/value\>/)
	{
       	 return "R $ratingsnum\r\n";
	}
}


# Convert XMLTV time format (YYYYMMDDmmss ZZZ) into VDR (secs since epoch)

sub xmltime2vdr
{
    my $xmltime=shift;
    my $secs = &Date::Manip::UnixDate($xmltime, "%s");
    return $secs + ( $adjust * 60 );
}

# Send info over SVDRP (thanks to Sky plugin)

sub SVDRPsend
{
    my $s = shift;
    if ($sim == 0)
    {
        print SOCK "$s\r\n";
    }
    else 
    {
        print "$s\r\n";
    } 
}

# Recv info over SVDRP (thanks to Sky plugin)

sub SVDRPreceive
{
    my $expect = shift | 0;
    
    if ($sim == 1)
    { return 0; }
    
    my @a = ();
    while (<SOCK>) {
        s/\s*$//; # 'chomp' wouldn't work with "\r\n"
        push(@a, $_);
        if (substr($_, 3, 1) ne "-") {
            my $code = substr($_, 0, 3);
            die("expected SVDRP code $expect, but received $code") if ($code != $expect);
            last;
        }
    }
    return @a;
}

sub EpgSend 
{
    my ($p_chanId, $p_chanName, $p_epgText, $p_nbEvent) = @_;
    # Send VDR PUT EPG
    SVDRPsend("PUTE");
    SVDRPreceive(354);
    SVDRPsend($p_chanId . $p_epgText . "c\r\n" . ".");
    SVDRPreceive(250);
    if ($verbose == 1 ) { warn("$p_nbEvent event(s) sent for $p_chanName\n"); }
}
# Process info from XMLTV file / channels.conf and send via SVDRP to VDR

sub ProcessEpg
{
    my @chanId;
    my @canMissing;
    my $chanline;
    my $epgfreq;
    while ( $chanline=<CHANNELS> )
    {
        # Split a Chan Line
        
        chomp $chanline;
        
        my ($channel_name, $freq, $param, $source, $srate, $vpid, $apid, $tpid, $ca, $sid, $nid, $tid, $rid, $xmltv_channel_name) = split(/:/, $chanline);
        
        if ( $source eq 'T' )
        { 
            $epgfreq=substr($freq, 0, 3);
        }
        else
        { 
            $epgfreq=$freq;
        }
        my $channel_more;
        ($channel_name_min,$channel_more) = split(/;/,$channel_name);
        if (!$xmltv_channel_name) {
            if(!$channel_name_min) {
                $chanline =~ m/:(.*$)/;
                if ($verbose == 1 ) { warn("Ignoring header: $1\n"); }
            } else {

                #Here we'll try to find $channel_name from TNT.XML !
		    my $channel_id;
		    my $found=0;
		    
		    for $pass (1..2) {
		    foreach $xmlline (@xmllines)
			{
    			    last if ($found!=0);
    			    chomp $xmlline;
		            $xmlline=xmltvtranslate($xmlline);
		            last if ($xmlline =~ m:\<programm:o); # don't process full file if not need !
    			    my $xmltv_ch_id = "$1" if ( $xmlline =~ m:\<channel id=\"(.*?)\"\>:o );
    			    $channel_id = $xmltv_ch_id if ($xmltv_ch_id);
		            my $xmltv_ch_name = "$1" if ( $xmlline =~ m:\<display-name\>(.*?)\<\/display:oi );
    			    # on doit comparer $xmltv_ch_name a $channel_name_min
    			    
    			    # on sort les accents et autres 
    			    
    			    $xmltv_ch_name =~ s/é/e/g;
    			    $xmltv_ch_name =~ s/è/e/g;
    			    $xmltv_ch_name =~ s/ê/e/g;
    			    $xmltv_ch_name =~ s/à/e/g;
    			    $xmltv_ch_name =~ s/â/e/g;
    			    $channel_name_min =~ s/é/e/g;
    			    $channel_name_min =~ s/è/e/g;
    			    $channel_name_min =~ s/ê/e/g;
    			    $channel_name_min =~ s/à/e/g;
    			    $channel_name_min =~ s/â/e/g;
    			    $xmltv_ch_name =~ s/\+//g;
    			    $channel_name_min =~ s/\+//g;
    			    $xmltv_ch_name =~ s/\W//g;
    			    $channel_name_min =~ s/\W//g;
    			    $xmltv_ch_name =~ s/\s//g;
    			    $channel_name_min =~ s/\s//g;
    			    $channel_name_min =~ s/HD$//;
    			    
    			    
    			    my $lg_xml = length($xmltv_ch_name);
    			    my $lg_ch  = length($channel_name_min);
    			    
    			    if ($xmltv_ch_name) { # if we have something
    				
    				# pass 1
    				if (($pass==1) &&
    				    ($lg_xml eq $lg_ch) &&
    				    ($xmltv_ch_name =~ m/$channel_name_min/i))
    				 {
				
				    print "found : $channel_id with $xmltv_ch_name for $channel_name_min\n";
		        	    $xmltv_channel_name=$channel_id;
		        	    $found=1;
		        	    #exit(0);
    				 }
    				# pass 
        			if (($pass==2) &&
    				    ($xmltv_channel_name ne $channel_id) && (
    				    ($xmltv_ch_name =~ m/$channel_name_min/i) ||
    				    (substr($xmltv_ch_name,0,$lg_ch) eq $channel_name_min) ||
    				    (substr($channel_name_min,0,$lg_xml) eq $xmltv_ch_name)
    				    ))
    				 {
				    print "found approx : $channel_id with $xmltv_ch_name for $channel_name_min\n";
		        	    $xmltv_channel_name=$channel_id;
		        	    $found=1;
    				 }
    			    
    			    }
    			    }
    			    
		            }
                if (($verbose == 1) && (!$xmltv_channel_name) ) { warn("Ignoring channel: $channel_name_min, no xmltv info\n"); } 

            }
            # If we haven't find an $xmltv_channel_name, so next
            next if (!$xmltv_channel_name);
        }
        my @channels = split ( /,/, $xmltv_channel_name);
         foreach my $myChannel ( @channels )
        {
        	# Save the Channel Entry
        	if ($nid>0) 
        	{
                push @chanId , [$myChannel,"C $source-$nid-$tid-$sid $channel_name\r\n",$channel_name];
        	}
        	else 
        	{
                push @chanId , [$myChannel,"C $source-$nid-$epgfreq-$sid $channel_name\r\n",$channel_name];
        	}
        }
    }

    # Set XML parsing variables    
    my $chanevent = 0;
    my $dc = 0;
    my $founddesc=0;
    my $foundcredits=0;
    my $creditscomplete=0;
    my $description = "";
    my $creditdesc = "";
    my $foundrating=0;
    my $setrating=0;
    my $genreinfo=0;
    my $gi = 0;
    my $chanCur = "";
    my $nbEventSent = 0;
    my $atLeastOneEpg = 0;
    my $epgText = "";
    my $pivotTime = time ();
    my $xmlline;
    
    # Find XML events
    
    foreach $xmlline (@xmllines)
    {
        chomp $xmlline;
        $xmlline=xmltvtranslate($xmlline);
        
        # New XML Program - doesn't handle split programs yet
        if ( ($xmlline =~ /\<programme/o ) && ( $xmlline !~ /clumpidx=\"1\/2\"/o ) && ( $chanevent == 0 ) )
        {
            my ( $chan ) = ( $xmlline =~ m/channel\=\"(.*?)\"/ );
            
            my $exist=-1;
            for $i ( 0 .. $#chanId ) {
                    $exist=$i if ($chanId[$i][0] eq $chan);
                            }
            if ( $exist<0 )
            {
                
               my $exist2=-1;
                for $i ( 0 .. $#chanMissing ) {
                        $exist2=$i if ($chanMissing[$i][0] eq $chan);
                                }
                if ( $exist2<0 )
                    {
                    if ($verbose == 1 ) { warn("$chan unknown in channels.conf\n"); }
	                push(@chanMissing,[$chan,1]);
                }
                next;
            }
            my ( $xmlst, $xmlet ) = ( $xmlline =~ m/start\=\"(.*?)\"\s+stop\=\"(.*?)\"/o );
            my $vdrst = &xmltime2vdr($xmlst);
            my $vdret = &xmltime2vdr($xmlet);
            if ($vdret < $pivotTime)
            {
                next;
            }
            if ( ( $chanCur ne "" ) && ( $chanCur ne $chan ) )
            {
                $atLeastOneEpg = 1;
                
                # we need to send event for all channels with same epg TF1, TF1 HD ....
                for $i ( 0 .. $#chanId ) {
                    if ($chanId[$i][0] eq $chanCur) {
            		    EpgSend ($chanId[$i][1],$chanId[$i][2], $epgText, $nbEventSent);
			}
                    }
                $epgText = "";
                $nbEventSent = 0;
            }
            $chanCur = $chan;
            $nbEventSent++;
            $chanevent = 1;
            my $vdrdur = $vdret - $vdrst;
            my $vdrid = $vdrst / 60 % 0xFFFF;
            
            # Send VDR Event
            
            $epgText .= "E $vdrid $vdrst $vdrdur 0\r\n";
        }
        
        if ( $chanevent == 0 )
        {
            next;
        }
        
        # XML Program Title
        $epgText .= "T $1\r\n" if ( $xmlline =~ m:\<title.*?\>(.*?)\</title\>:o );
        
        # XML Program Sub Title
        $epgText .= "S $1\r\n" if ( $xmlline =~ m:\<sub-title.*?\>(.*?)\</sub-title\>:o );
        
        # XML Program description at required verbosity
        
        if ( ( $founddesc == 0 ) && ( $xmlline =~ m/\<desc.*?\>(.*?)\</o ) )
        {
            if ( $descv == $dc )
            {
                # Send VDR Description & end of event
                $description .= "$1|";
                $founddesc=1;
            }
            else
            {
                # Description is not required verbosity
                $dc++;
            }
        }
        if ( ( $foundcredits == 0 ) && ( $xmlline =~ m/\<credits\>/o ) )
        {
                $foundcredits=1;
		$creditdesc="";
            }

	if ( ( $foundcredits == 1 ) && ( $xmlline =~ m:\<.*?\>(.*?)\<:o ) )
	{		
		my $desc;
		my $type;
		$desc = $1;
		$temp = "";
		if ( $xmlline =~ m:\<(.*?)\>:o )
		{
		$type = ucfirst $1;
		}
		$creditdesc .= "$type $desc|";
        }
	if ( ( $foundcredits== 1) && ( $xmlline =~ m/\<\/credits\>/o ) ) 
	{
		$foundcredits = 0;
		$creditscomplete = 1;
	}
        if ( ( $foundrating == 0 ) && ( $xmlline =~ m:\<rating.*?\=(.*?)\>:o ) )
        {
                $foundrating=1;

        }
        if ( ( $foundrating == 1 ) && ( $ratings == 0 ) && ( $xmlline =~ m:\<value.*?\>(.*?)\<:o ) )
        {
            if ( $setrating == 0 )
            {
				my $ratingstxt;
				my $ratingsnum;
				my $ratingsline;
				my $tmp;
				foreach my $ratingsline ( @ratinglines )
				{
					my ($ratingstxt, $ratingsnum) = split(/:/, $ratingsline);
					$tmp=ratings_id($xmlline, $ratingstxt, $ratingsnum);
					if ($tmp)
					{
       			 			last; # break out of the while loop
    					}
		
				}
				if ($tmp) {
					$epgText .=$tmp;
	                		$setrating=1;
					$description .= "$1|";
				}
	


            }
        }
	if ( $genre == 0 )
	{
		if ( ( $genreinfo == 0 ) && ( $xmlline =~ m:\<category.*?\>(.*?)\</category\>:o ) )
		{
			if ( $genre == $gi )
			{
				my $genretxt;
				my $genrenum;
				my $genreline;
				my $tmp;
					foreach my $genreline ( @genlines )
					{
					my ($genretxt, $genrenum) = split(/:/, $genreline);
					$tmp=genre_id($xmlline, $genretxt, $genrenum);
					if ($tmp)
					{
       			 			last; # break out of the while loop
    					}
				}
				if ($tmp) {
					$epgText .=$tmp;
					$description .= "$genretxt|";
					$gi++;
					$genreinfo=1;
				}
			}
			else
			{
				# No genre information asked
				$genre++;
			}
		} 
	} 
	else
	{
	$genreinfo=1;
	}

        # No Description and or Genre found
        
        if (( $xmlline =~ /\<\/programme/o )) 
        {
            if (( $founddesc == 0 ) || ( $genreinfo == 0 ))
            { 
                if (( $founddesc == 0 ) && ( $genreinfo == 0 )) {
		$epgText .= "D Info Not Available\r\n";
		$epgText .= "G 0\r\n";
                $epgText .= "e\r\n";
		}
		if  (( $founddesc == 0 ) && ( $genreinfo == 1 )) {
		$epgText .= "D Info Not Available\r\n";
                $epgText .= "e\r\n";
		}
		if  (( $founddesc == 1 ) && ( $genreinfo == 0 )) {
		$epgText .= "D $description$creditdesc\r\n";
		$epgText .= "G 0\r\n";
                $epgText .= "e\r\n";
		}
            }
	    else 
	    {
		$epgText .= "D $description$creditdesc\r\n";
		$epgText .= "e\r\n";
	    }
            $chanevent=0 ;
            $dc=0 ;
            $founddesc=0 ;
	    $genreinfo=0;
	    $foundrating=0;
	    $setrating=0;
	    $gi=0;
	    $creditscomplete = "";
	    $description = "";
        }
    }
    
    if ( $atLeastOneEpg )
    {
    # we need to send event for all channels with same epg TF1, TF1 HD ....
    for $i ( 0 .. $#chanId ) {
            if ($chanId[$i][0] eq $chanCur) {
    		    EpgSend ($chanId[$i][1],$chanId[$i][2], $epgText, $nbEventSent);
		}
            }
    }
}

#---------------------------------------------------------------------------
# main

use Socket;

my $Usage = qq{
Usage: $0 [options] -c <channels.conf file> -x <xmltv datafile> 
    
Options:
 -a (+,-) mins  	Adjust the time from xmltv that is fed
                        into VDR (in minutes) (default: 0)	 
 -c channels.conf	File containing modified channels.conf info
 -d hostname            destination hostname (default: localhost)
 -h			Show help text
 -g genre.conf   	if xmltv source file contains genre information then add it
 -r ratings.conf   	if xmltv source file contains ratings information then add it
 -l description length  Verbosity of EPG descriptions to use
                        (0-2, 0: more verbose, default: 0)
 -p port                SVDRP port number (default: 6419)
 -s			Simulation Mode (Print info to stdout)
 -t timeout             The time this program has to give all info to 
                        VDR (default: 300s) 
 -v             	Show warning messages
 -x xmltv output 	File containing xmltv data
    
};

die $Usage if (!getopts('a:d:p:l:g:r:t:x:c:vhs') || $opt_h);

$verbose = 1 if $opt_v;
$sim = 1 if $opt_s;
$adjust = $opt_a || 0;
my $Dest   = $opt_d || "localhost";
my $Port   = $opt_p || 6419;
my $descv   = $opt_l || 0;
my $Timeout = $opt_t || 300; # max. seconds to wait for response
my $xmltvfile = $opt_x  || die "$Usage Need to specify an XMLTV file";
my $channelsfile = $opt_c  || die "$Usage Need to specify a channels.conf file";
$genfile = $opt_g if $opt_g;
$ratingsfile = $opt_r if $opt_r;

# Check description value
if ($genfile) {
$genre=0;
my @genrelines;
# Read the genres.conf stuff into memory - quicker parsing
open(GENRE, "$genfile") || die "cannot open genres.conf file";
while ( <GENRE> ) {
	s/#.*//;            # ignore comments by erasing them
	next if /^(\s)*$/;  # skip blank lines
	chomp;
	push @genlines, $_;
}
close GENRE;
}
else {
$genre=1;
}

if ($ratingsfile) {
$ratings=0;
my @ratinglines;
# Read the genres.conf stuff into memory - quicker parsing
open(RATINGS, "$ratingsfile") || die "cannot open genres.conf file";
while ( <RATINGS> ) {
	s/#.*//;            # ignore comments by erasing them
	next if /^(\s)*$/;  # skip blank lines
	chomp;
	push @ratinglines, $_;
}
close RATINGS;
}
else {
$ratings=1;
}


if ( ( $descv < 0 ) || ( $descv > 2 ) )
{
    die "$Usage Description out of range. Try 0 - 2";
}
# Read all the XMLTV stuff into memory - quicker parsing

open(XMLTV, "$xmltvfile") || die "cannot open xmltv file";
@xmllines=<XMLTV>;
close(XMLTV);

# Now open the VDR channel file

open(CHANNELS, "$channelsfile") || die "cannot open channels.conf file";

# Connect to SVDRP socket (thanks to Sky plugin coders)

if ( $sim == 0 )  
{
    $SIG{ALRM} = sub { die("timeout"); };
    alarm($Timeout);
    
    my $iaddr = inet_aton($Dest)                   || die("no host: $Dest");
    my $paddr = sockaddr_in($Port, $iaddr);
    
    my $proto = getprotobyname('tcp');
    socket(SOCK, PF_INET, SOCK_STREAM, $proto)  || die("socket: $!");
    connect(SOCK, $paddr)                       || die("connect: $!");
    select((select(SOCK), $| = 1)[0]);
}

# Look for initial banner
SVDRPreceive(220);
SVDRPsend("CLRE");
SVDRPreceive(250);

# Do the EPG stuff
ProcessEpg();

# Lets get out of here! :-)

SVDRPsend("QUIT");
SVDRPreceive(221);

close(SOCK);
