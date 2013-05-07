#!/usr/bin/python

#
# upstreamchecker is a script to check the differences between OBS projects
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# Author(s): 
#   - Marko Saukko <marko.saukko@jollamobile.com>, Sage - #nemomobile @ Freenode
#

import subprocess
import re
from optparse import OptionParser

API_URL="https://api.merproject.org/"

parser = OptionParser()
parser.add_option("","--show-changelog",dest="show_changelog", action="store_true",
                  help="Show changelog when there is one.")
parser.add_option("","--show-bugnumbers",dest="show_bugnumbers", action="store_true",
                  help="Show bugnumbers that are in changelog")
parser.add_option("","--show-new-pkgs", dest="show_new_pkgs", action="store_true",
                  help="Show packages that are new in the destination.")
parser.add_option("","--show-only-removed-changes", dest="show_only_removed_changes", action="store_true",
                  help="Show only the lines in changelog that start with -.")
parser.add_option("-A","--api-url", dest="apiurl", default=API_URL,
                  help="OBS API URL")
parser.add_option("-S","--source-project",dest="srcprj", default=None,
                  help="Source project.")
parser.add_option("-D","--destination-project",dest="dstprj", default=None,
                  help="Destination project.")
parser.add_option("-c","--create-creq-string",dest="create_creq_str", action="store_true",
                  help="Create creq string for osc.")
parser.add_option("-d","--add-deleted",dest="add_deleted", action="store_true",
                  help="Add deleted packages to creq")
parser.add_option("","--show-packages-without-diff", dest="show_no_diff", action="store_true",
                  help="Show when packages do not have difference.")
parser.add_option("","--add-without-changes", dest="add_without_changes", action="store_true",
                  help="Add packages without changes to creq list.")
(options,args) = parser.parse_args()

CHANGES_TMP="changes.tmp"

if not options.srcprj or not options.dstprj:
    print "ERROR: you need to define both source and destination projects."
    exit(1)

def readpkglist(project):
  pkglistcmd = "osc -A %s ls %s" % (options.apiurl, project)
  pkglistcmd = pkglistcmd.split(" ")

  print "Reading list of packages from %s..." % (project)
  packages = subprocess.Popen(pkglistcmd,stdout=subprocess.PIPE).communicate()[0]
  return packages.split("\n")

packages_srcprj = readpkglist(options.srcprj);
packages_dstprj = readpkglist(options.dstprj);

all_bugnums = []
packages_with_changes = []

print "Checking changes between projects %s and %s" % (options.srcprj,options.dstprj)

for package in packages_srcprj:
    package = package.strip()
    
    # Skip empty lines and patterns
    if package == "" or package == "_pattern":
        continue
    
    pkgdiffcmd = "osc -A %s rdiff %s %s %s" % (options.apiurl, options.dstprj, package, options.srcprj)

    pkgdiffcmd = pkgdiffcmd.split(" ")
    pkgdiff = subprocess.Popen(pkgdiffcmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT).communicate()[0]

    if re.search("HTTP Error 404: Not Found", pkgdiff) \
       or re.search("remote error: Not Found", pkgdiff) \
       or re.search("unknown_package", pkgdiff):
        if options.show_new_pkgs:
            print "\n\n+++++ Package %s is only in %s." % (package, options.srcprj)
        packages_with_changes.append(package)
        continue

    if pkgdiff == "":
        if options.show_no_diff:
            print "\n\n===== Package '%s' is the same in '%s' and '%s'. Could be removed from '%s'?" % (package, options.srcprj, options.dstprj, options.srcprj)
            print "===== https://build.pub.meego.com/package/show?package=%s&project=%s" % (package,options.srcprj)
        continue
    
    pkgdiff = re.split('\sIndex:\s(\w|_|:|-|\.)+\.changes\s', pkgdiff)
    
    # At times the .changes is the first and split creates empty slot
    if pkgdiff[0] == "":
        pkgdiff.pop(0)
    
    pkg_changes = None

    for dpart in pkgdiff:
        if re.search("\+\+\+\s(\w|_|:|-|\.)+\.changes\s", dpart):
            pkg_changes = dpart
            break
    
    if not pkg_changes:
        print "\n\n????? ERROR: No changes found for package '%s', bug in script?" % (package)
        print "Called cmd: %s" % (" ".join(pkgdiffcmd))
        if options.add_without_changes:
            packages_with_changes.append(package)
        continue

    packages_with_changes.append(package)

    # Do another split so we get rid off changes after changelog.
    pkgdiff = re.split('\nIndex:', pkg_changes, maxsplit=2)

    changes = pkgdiff[0]

    # Put changelog to temp file.
    fh = open(CHANGES_TMP,"w")
    fh.write(changes)
    fh.close()

    if options.show_bugnumbers:
        # We want to check only added diff lines
        s = subprocess.Popen(["grep", "-v", "^-", CHANGES_TMP], stdout = subprocess.PIPE)
        added_changes = s.communicate()[0]
        
        bugnumstmp = re.findall('((?:\s#|NEMO#|MER#|BMC|BMC\s|Bmc#|bmc#|BMC#|BMC-)\d+)',added_changes,re.IGNORECASE)
        bugnums = []

        for bugnumtmp in bugnumstmp:
            bugnum = re.search('\d+',bugnumtmp)
            bugnums.append(int(bugnum.group(0)))
            all_bugnums.append(int(bugnum.group(0)))

        # Remove duplicated items from a list by converting it to set and then back to list.
        bugnums = list(set(bugnums))
        bugnums.sort()
        print "Bug numbers for %s: %s" % (package, ",".join(str(i) for i in bugnums))
    
    if options.show_only_removed_changes:
        s = subprocess.Popen(["grep", "^-", CHANGES_TMP], stdout = subprocess.PIPE)
        removed_changes = s.communicate()[0]
        if ( removed_changes.strip() != "" ):
            print "\n\n### Package '%s' has following removed changelog entries between projects '%s' and '%s':\n%s" % (package, options.dstprj, options.srcprj, removed_changes)
        continue

    # No need to continue if changelog is not wanted.
    if not options.show_changelog:
        continue

    print "\n\n##### Package '%s' diff between projects '%s' and '%s':\n%s" % (package, options.dstprj, options.srcprj,changes)

if options.show_bugnumbers:
    all_bugnums = list(set(all_bugnums))
    all_bugnums.sort()
    print "Total bugs (%s) fixed: %s" % (len(all_bugnums), ",".join(str(i) for i in all_bugnums))

creq_str = ""

if options.create_creq_str:
    for package in packages_with_changes:
        creq_str += "-a submit %s %s %s " % (options.srcprj, package, options.dstprj)

if options.add_deleted:
   for package in packages_dstprj:
       if package in packages_srcprj:
           continue
       print "Package %s removed from project '%s'." % (package, options.dstprj)
       if options.create_creq_str:
          creq_str += "-a delete %s %s " % (options.dstprj, package) 

if options.create_creq_str:
    print "### osc creq string ###"
    if creq_str:
        print "osc -A %s creq -m fixes %s" % (options.apiurl, creq_str)
    else:
        print "No changes so not creating creq string."

