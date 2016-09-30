#!/usr/bin/python3

from bs4 import BeautifulSoup as bs
import sys
import argparse
import subprocess
import getpass
import requests

parser = argparse.ArgumentParser(description='Perform merge request')
parser.add_argument('-b', '--bugz', help='Bug number', required=True, type=int)
parser.add_argument('-r', '--revision', help='Patch revision', required=True, type=int)
parser.add_argument('-n', '--num', help='No of patches you are pushing', required=True, type=int)
args = vars(parser.parse_args())

kgit = "gitcge7.mvista.com:/mvista/git/cge7/contrib/kernel.git"
msg = "Merge to mvl7-3.10/cge_dev"
url = "git://gitcge7.mvista.com/cge7/contrib/kernel.git"

bug_no = str(args['bugz'])
revision = str(args['revision'])
p_count = str(args['num'])

bugz_login_url = 'http://bugz.mvista.com/show_bug.cgi?id='+bug_no
bugz_post_url = 'http://bugz.mvista.com/process_bug.cgi'

tag = 'mvl7-3.10/cge_dev-'+bug_no+'-'+'V'+revision
start_c = 'HEAD~'+p_count
merg_req_f = bug_no+'-'+'V'+revision+'.file'

cmd_timeout = 180


def execute_cmd(cmd, prstr):
    "Execute the bash commands encoded in cmd and handle timeouts"
    try:
        p = subprocess.Popen(cmd, shell=True)
        p.wait(timeout=cmd_timeout)
        if (p.returncode == 0):
            print (prstr)
        else:
            print ("The command:%s pid:%d failed... exiting \n" % (cmd, p.pid))
            sys.exit(1)
    except subprocess.TimeoutExpired:
        p.kill()
        print ("The command:%s pid:%d timed out, but continuing \n" % (cmd, p.pid))
        return

cmd = 'git tag -m "%s" "%s"' % (msg, tag)
execute_cmd(cmd, "Successfully created tag : %s\n" % (tag))

print ("Pushing the tag : %s to %s" % (tag, url))
username = input("Please enter your bugzilla user name\n")
cmd = 'git push "%s"@"%s" "+%s"' % (username, kgit, tag)
execute_cmd(cmd, "Successfully pushed the tag to %s\n" % (kgit))

cmd = 'git request-pull %s %s %s | tee %s' % (start_c, url, tag, merg_req_f)
execute_cmd(cmd, "Successfully generated pull request\n")

print ("Trying to update bugzilla fields for bug %s" % str(args['bugz']))
bugz_pword = getpass.getpass('Please enter your bugzilla password:')

acc_details = {
    'Bugzilla_login': username,
    'Bugzilla_password': bugz_pword,
}

upd_d = {
    'id': bug_no,
    'status_whiteboard': 'GitMergeRequest',
    'newcc': 'cge7-kernel-gatekeepers@mvista.com, akuster',
}


def handle_bugz_err(status, prstr):
    if (status != requests.codes.ok):
        print(prstr)
        print("Exiting..")
        sys.exit(1)


def check_err(err, got):
    if (err == got):
        print (err)
        print("Exiting..")
        sys.exit(1)

with requests.session() as s:
    try:
        r = s.post(bugz_login_url, data=acc_details)
        handle_bugz_err(r.status_code, "Bugzilla login falied\n")
        soup = bs(r.text, 'lxml')
        check_err("Invalid Username Or Password", soup.title.string)

        r = s.get(bugz_login_url)
        soup = bs(r.text, 'lxml')
        upd_d['delta_ts'] = soup.find('input', {'name': 'delta_ts'}).get('value')
        upd_d['token'] = soup.find('input', {'name': 'token'}).get('value')

        txt = open(merg_req_f)
        upd_d['comment'] = txt.read()
        r = s.post(bugz_post_url, data=upd_d)
        print("Finished....... bye.")
    except requests.exceptions.Timeout:
        print("Connection timed out")
        sys.exit(1)
    except requests.exceptions.RequestException as e:
        print (e)
        sys.exit(1)
