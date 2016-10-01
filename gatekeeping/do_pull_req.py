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

bug_no = str(args['bugz'])
revision = str(args['revision'])
p_count = str(args['num'])

repo_details = [
        {
            'repo': 'CGE7',
            'origin': 'gitcge7.mvista.com:/mvista/git/cge7/kernel/mvl7kernel.git',
            'pushto': 'gitcge7.mvista.com:/mvista/git/cge7/contrib/kernel.git',
            'tag_msg': 'Merge to mvl7-3.10/cge_dev',
            'git_tag': 'mvl7-3.10/cge_dev-',
            'url': 'git://gitcge7.mvista.com/cge7/contrib/kernel.git',
            },
        {
            'repo': 'CGX2.0',
            'origin': 'gitcgx.mvista.com:/mvista/git/cgx/CGX2.0/kernel/linux-mvista-2.0.git',
            },
        ]

bugz_login_url = 'http://bugz.mvista.com/show_bug.cgi?id='+bug_no
bugz_post_url = 'http://bugz.mvista.com/process_bug.cgi'

start_c = 'HEAD~'+p_count
merg_req_f = bug_no+'-'+'V'+revision+'.file'

cmd_timeout = 180


def error_exit(prstr):
        print(prstr)
        print("Exiting..")
        sys.exit(1)


def execute_cmd(cmd, prstr):
    "Execute the bash commands encoded in cmd and handle timeouts"
    try:
        p = subprocess.Popen(cmd, shell=True)
        p.wait(timeout=cmd_timeout)
        if (p.returncode == 0):
            print (prstr)
        else:
            error_exit("The command:%s pid:%d failed" % (cmd, p.pid))
    except subprocess.TimeoutExpired:
        p.kill()
        print ("The command:%s pid:%d timed out, but continuing \n" % (cmd, p.pid))
        return


def find(lst, key, value):
    for i, dic in enumerate(lst):
        if dic[key] == value:
            return i
    return -1


def form_repo_data(idx):
    print("%s repo identified" % (repo_details[idx]['repo']))
    global contrib, msg, contrib_url, tag
    contrib = repo_details[idx]['pushto']
    msg = repo_details[idx]['tag_msg']
    contrib_url = repo_details[idx]['url']
    tag = repo_details[idx]['git_tag']+bug_no+'-V'+revision


def identify_repo():
    cmd = 'git config --get remote.origin.url > %s' % (merg_req_f)
    rc = execute_cmd(cmd, "")
    txt = open(merg_req_f)
    tmp = txt.readline()
    txt.close()
    tmp = tmp.splitlines()
    if (tmp):
        tmp = tmp[0].split('@')
        if (len(tmp) != 2):
            error_exit("Not an MV type repo\n")

        idx = find(repo_details, 'origin', tmp[1])
        if (idx == -1):
            error_exit("Unable to find the repo type\n")

        form_repo_data(idx)
    else:
        error_exit("Not an MV type repo\n")

identify_repo()
cmd = 'git tag -m "%s" "%s"' % (msg, tag)
execute_cmd(cmd, "Successfully created tag : %s\n" % (tag))

print ("Pushing the tag : %s to %s" % (tag, contrib_url))
username = input("Please enter your bugzilla user name\n")
cmd = 'git push "%s"@"%s" "+%s"' % (username, contrib, tag)
execute_cmd(cmd, "Successfully pushed the tag to %s\n" % (contrib))

cmd = 'git request-pull %s %s %s | tee %s' % (start_c, contrib_url, tag, merg_req_f)
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


def check_err(err, got):
    if (err == got):
        error_exit(err)

with requests.session() as s:
    try:
        r = s.post(bugz_login_url, data=acc_details)
        soup = bs(r.text, 'lxml')
        check_err("Invalid Username Or Password", soup.title.string)

        r = s.get(bugz_login_url)
        soup = bs(r.text, 'lxml')
        upd_d['delta_ts'] = soup.find('input', {'name': 'delta_ts'}).get('value')
        upd_d['token'] = soup.find('input', {'name': 'token'}).get('value')

        txt = open(merg_req_f)
        upd_d['comment'] = txt.read()
        txt.close()
        r = s.post(bugz_post_url, data=upd_d)
        print("Finished....... bye.")
    except requests.exceptions.Timeout:
        error_exit("Connection timed out")
    except requests.exceptions.RequestException as e:
        error_exit(e)
