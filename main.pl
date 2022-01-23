use strict;
use warnings;
use autodie;

use Data::Dumper;
use Digest::MD5;
use File::Copy;
use File::Basename;
use File::Path;
use File::stat;
use Path::Tiny;
use feature qw(switch);

### READ CONFIG ###

my $config_path = path($ENV{"HOME"}, ".clean_files");
# my $config_path = path(".clean_files");
my %config = ();

open (_FH, $config_path) or die "Unable to open config file: $!";
while (<_FH>) {
    chomp;                  # no newline
    s/#.*//;                # no comments
    s/^\s+//;               # no leading white
    s/\s+$//;               # no trailing white
    next unless length;     # anything left?
    my ($var, $value) = split(/\s*=\s*/, $_, 2);
    if (($var eq 'TEMPORARY') || ($var eq 'RESTRICTED')) {
        $config{$var} = [split(',', $value)];
    } else {
        $config{$var} = $value;
    }
}
close _FH;

### INITIALIZE MAIN VARIABLES ###

my @files = ();
my @deleted = ();
my $origin_dir = path($config{ORIGIN_DIR});
my $data_dir = path($config{DATA_DIR});

### INITIALIZE SUBROUTINES ###

sub read_content {
    open(FILE, @_[0]) or next;
    binmode(FILE);
    return Digest::MD5->new->addfile(*FILE)->hexdigest;
}

sub ls {
    foreach (@_) {
        my $iter = $_->iterator;
        while (my $file = $iter->()) {
            if ($file->is_dir()) {
                ls($file);
            } else {
                push @files, {
                    "name", basename($file),
                    "path", $file->stringify(),
                    "content", read_content($file->stringify()),
                    "attributes", stat($file)->mode & 0777, # this will show in decimal when printed
                    "date", stat($file)->mtime,
                    "suggestions", ()
                };
            }
        }
    }
}

sub find {
    foreach my $file1 (@_) {
        foreach my $file2 (@_) {
            next if $file1->{path} eq $file2->{path};

            # check if two files have the same content
            if ($file1->{content} eq $file2->{content}) {
                if ($file1->{date} < $file2->{date}) {
                    push @{$file1->{suggestions}}, {
                        "type", 1,
                        "file", $file2
                    }
                }
            }

            # check if there is a newer version of a file with the same name
            if ($file1->{name} eq $file2->{name}) {
                if ($file1->{content} ne $file2->{content}) {
                    if ($file1->{date} < $file2->{date}) {
                        push @{$file1->{suggestions}}, {
                            "type", 3,
                            "file", $file2
                        }
                    }
                }
            }
        }

        # check if file is empty
        if (($file1->{content}) eq '') {
            push @{$file1->{suggestions}}, {
                "type", 2
            }
        }

        # check if file is considered as a temporary file
        foreach (@{$config{TEMPORARY}}) {
            if ($file1->{name} =~ /\Q$_\E\z/) {
                push @{$file1->{suggestions}}, {
                    "type", 4
                }
            }
        }

        # check if this file has non-standard attributes
        if ($file1->{attributes} != $config{ATTRIBUTES}) {
            push @{$file1->{suggestions}}, {
                "type", 5
            }
        }

        # check if file name has restricted characters in it
        foreach (@{$config{RESTRICTED}}) {
            if ($file1->{name} =~ m/\Q$_\E/) {
                push @{$file1->{suggestions}}, {
                    "type", 6
                }
            }
        }

        # check if file is not in origin_dir
        if (!($file1->{path} =~ m/\Q$config{ORIGIN_DIR}\E/)) {
            push @{$file1->{suggestions}}, {
                "type", 7
            }
        }
    }
}

sub show {
    print Dumper(@files), "\n";
}

sub delete_files_and_suggestions {
    foreach (@_) {
        unlink ($_->{path});
        push @deleted, $_->{path};
        print "deleted ", $_->{path}, "\n";
    }
}

sub replace_restricted_signs {
    my $result = @_[0];
    foreach (@{$config{RESTRICTED}}) {
        $result =~ s/\Q$_\E/_/g;
    }
    return ($result);
}

sub move_to_origin {
    my $result = @_[0];
    $result =~ s/\Q$config{DATA_DIR}\E/\Q$config{ORIGIN_DIR}\E/;
    $result =~ s/\\//g;
    mkpath($result);
    move(@_[0], $result) or die "Unable to move: $!";
    push @deleted, @_[0];
    print "moved ", @_[0], "\n";
}

sub suggest {
    foreach my $file (@files) {
        foreach my $suggestion (@{$file->{suggestions}}) {
            next if ($suggestion->{file}->{path} ~~ @deleted);
            next if ($file->{path} ~~ @deleted);
            given ($suggestion->{type}) {
                when (1) {
                    print "Would you like to delete ", $suggestion->{file}->{path}, ", which has the same content as ", $file->{path}, "? [y/n]\n";
                    if ("y\n" eq <STDIN>) {
                        delete_files_and_suggestions($suggestion->{file});
                    }
                }
                when (2) {
                    print "Would you like to delete ", $file->{path}, ", which is an empty file? [y/n]\n";
                    if ("y\n" eq <STDIN>) {
                        delete_files_and_suggestions($file);
                    }
                }
                when (3) {
                    print "Would you like to delete ", $file->{path}, ", which appears to be an older version of ", $suggestion->{file}->{path}, "? [y/n]\n";
                    if ("y\n" eq <STDIN>) {
                        delete_files_and_suggestions($file);
                    }
                }
                when (4) {
                    print "Would you like to delete ", $file->{path}, ", which is considered a temporary file? [y/n]\n";
                    if ("y\n" eq <STDIN>) {
                        delete_files_and_suggestions($file);
                    }
                }
                when (5) {
                    print "Would you like to change the attributes of ", $file->{path}, ", to a more standard one? [y/n]\n";
                    if ("y\n" eq <STDIN>) {
                        chmod $config{ATTRIBUTES}, $file->{path};
                    }
                }
                when (6) {
                    print "Would you like to change the name of ", $file->{path}, ", which contains signs that are considered restricted? [y/n]\n";
                    if ("y\n" eq <STDIN>) {
                        rename($file->{path}, replace_restricted_signs($file->{path}));
                    }
                }
                when (7) {
                    print "Would you like to move ", $file->{path}, ", to, ", $config{ORIGIN_DIR}, "? [y/n]\n";
                    if ("y\n" eq <STDIN>) {
                        move_to_origin($file->{path});
                    }
                }
                default {
                    print "This suggestion has not been implemented yet!\n";
                }
            }
        }
    }
}

### RUN ###

ls($data_dir);
find(@files);
# show(@files);
suggest(@files);
