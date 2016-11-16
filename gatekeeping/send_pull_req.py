#!/usr/bin/python3

from bs4 import BeautifulSoup as bs
import sys
import argparse
import subprocess
import getpass
import requests
import pexpect
import re

bug_no = ''
revision = ''
p_count = ''
start = ''
start_c = ''

contrib = ''
msg = ''
contrib_url = ''
tag = ''
username = ''
mvista_id = ''
debug = ''
tag_is_created = ''

repo_details = [
    {
        'repo': 'CGE7',
        'origin': 'gitcge7.mvista.com:/mvista/git/cge7/kernel/mvl7kernel.git',
        'pushto': 'gitcge7.mvista.com:/mvista/git/cge7/contrib/kernel.git',
        'url': 'git://gitcge7.mvista.com/cge7/contrib/kernel.git',
        },
    {
        'repo': 'CGX2.0',
        'origin': 'gitcgx.mvista.com:/mvista/git/cgx/CGX2.0/kernel/linux-mvista-2.0.git',
        'pushto': 'gitcgx.mvista.com:/mvista/git/cgx/contrib/kernel.git',
        'url': 'git://gitcgx.mvista.com/cgx/contrib/kernel.git',
        },
    {
        'repo': 'CGX1.8',
        'origin': 'gitcgx.mvista.com:/mvista/git/cgx/CGX/kernels/linux-mvista-1.8.git',
        'pushto': 'gitcgx.mvista.com:/mvista/git/cgx/contrib/kernel.git',
        'url': 'git://gitcgx.mvista.com/cgx/contrib/kernel.git',
        },
]


def dbg_print(str):
    if (debug == 1):
        if (str):
            print(str)


def error_exit(prstr):
    print(prstr)
    print("Exiting..")
    if (tag_is_created == 1):
        run_cmd('git tag -d %s > /dev/null' % (tag))
    sys.exit(1)


def run_cmd(cmd, *argv):
    leng = len(argv)
    sstr = ""
    fstr = ""

    if (leng):
        fstr = argv[0]
        if (leng > 1):
            sstr = argv[1]

    try:
        op = subprocess.check_output(cmd, shell=True, universal_newlines=True)
        dbg_print(sstr)
        return op
    except subprocess.CalledProcessError as e:
        error_exit(fstr)


def find(lst, key, value):
    for i, dic in enumerate(lst):
        if dic[key] == value:
            return i
    return -1


def form_repo_data(idx, remote_branch):
    global contrib, msg, contrib_url, tag
    dbg_print("%s repo identified." % (repo_details[idx]['repo']))
    dbg_print("Your changes target the remote branch:%s" % (remote_branch))
    contrib = repo_details[idx]['pushto']
    contrib_url = repo_details[idx]['url']
    msg = 'Merge to %s' % (remote_branch)
    tag = '%s-%s-V%s' % (remote_branch, bug_no, revision)


def identify_user():
    global username, mvista_id
    username = run_cmd('git config user.name', "Please configure username for the git repo").splitlines()[0]
    mvista_id = run_cmd('git config user.email', "Please configure email-id for the git repo").splitlines()[0]
    if not (re.match(r'.*.+@mvista.com', mvista_id)):
        error_exit("User's email-ID is not from the domain mvista.com")

    mvista_id = mvista_id.split('@')[0]


def identify_repo():
    identify_user()
    url = run_cmd('git config --get remote.origin.url', "Please make sure that you are inside a valid git repository").splitlines()[0]
    match = re.compile(mvista_id+'@.*.')
    if not (re.match(match, url)):
            error_exit("Not an MV type repo\n")

    idx = find(repo_details, 'origin', url.split('@')[1])
    if (idx == -1):
        error_exit("Unable to find the repo type\n")

    # Now identify the remote tracking branch of the current branch
    remote_br = run_cmd('git rev-parse --abbrev-ref --symbolic-full-name @{u}', "Unable to find the remote branch").splitlines()[0]
    remote_br = remote_br.split('/', 1)[1]
    form_repo_data(idx, remote_br)


def mark_start_commit():
    global start_c
    if (p_count == 'None' and start == 'None'):
        error_exit("Please specify a start commit for making the merge request; use -s or -n")

    if (p_count != 'None'):
        start_c = 'HEAD~'+p_count
    elif (start != 'None'):
        start_c = start


def parse_args():
    global bug_no, revision, p_count, start, debug
    parser = argparse.ArgumentParser(description='Perform merge request')
    parser.add_argument('-b', help='Bug number', required=True, type=int)
    parser.add_argument('-r', help='Patch revision', required=True, type=int)
    parser.add_argument('-n', help='No of patches you are pushing', required=False, type=int)
    parser.add_argument('-s', help='Start commit for merge request', required=False, type=str)
    parser.add_argument('-v', help='Print verbose messages', action="store_true")
    args = vars(parser.parse_args())

    if (args['v']):
        debug = 1

    bug_no = str(args['b'])
    revision = str(args['r'])
    p_count = str(args['n'])
    start = str(args['s'])


def check_err(err, got):
    if (err == got):
        error_exit(err)


def update_bugz_fields(uname, pword, cmnt):
    bugz_login_url = 'http://bugz.mvista.com/show_bug.cgi?id='+bug_no
    bugz_post_url = 'http://bugz.mvista.com/process_bug.cgi'

    acc_details = {
        'Bugzilla_login': uname,
        'Bugzilla_password': pword,
    }

    upd_d = {
        'id': bug_no,
        'status_whiteboard': 'GitMergeRequest',
        'newcc': 'cge7-kernel-gatekeepers@mvista.com, akuster',
    }

    with requests.session() as s:
        try:
            r = s.post(bugz_login_url, data=acc_details)
            soup = bs(r.text, 'lxml')
            check_err("Invalid Username Or Password", soup.title.string)

            r = s.get(bugz_login_url)
            soup = bs(r.text, 'lxml')
            upd_d['delta_ts'] = soup.find('input', {'name': 'delta_ts'}).get('value')
            upd_d['token'] = soup.find('input', {'name': 'token'}).get('value')
            upd_d['comment'] = cmnt

            r = s.post(bugz_post_url, data=upd_d)
        except requests.exceptions.Timeout:
            error_exit("Connection timed out")
        except requests.exceptions.RequestException as e:
            error_exit(e)


parse_args()
mark_start_commit()
identify_repo()

dbg_print("Generating pull request with the details")
dbg_print("----------------------------------------")
dbg_print("Username: %s" % (username))
dbg_print("Bugzilla-ID: %s" % (mvista_id))
dbg_print("----------------------------------------")

bugz_pword = getpass.getpass('Please enter bugzilla password for %s:' % (mvista_id))

run_cmd('git tag -m "%s" "%s"' % (msg, tag), 'Please try again after manually deleting the tag', 'tag: %s created\n' % (tag))
tag_is_created = 1

dbg_print("Pushing the tag: %s to %s" % (tag, contrib_url))
cmd = 'git push "%s"@"%s" "+%s"' % (mvista_id, contrib, tag)
exp_str1 = 'password'
exp_str2 = 'fatal: Could not read from remote repository.'
exp_str3 = 'Permission denied, please try again.'
child = pexpect.spawn(cmd)
index = child.expect([exp_str1, exp_str2, pexpect.EOF], timeout=180)
if (index == 0):
    child.sendline(bugz_pword)
else:
    child.close()
    error_exit("Unable to read from the remote git repo")

index = child.expect([pexpect.TIMEOUT, exp_str3, exp_str2, pexpect.EOF], timeout=180)
if (index == 3):
    dbg_print('Successfully pushed the tag to %s\n' % (contrib))
elif (index == 0):
    print("Timeout during pushing the tag to contrib, but continuing")
else:
    child.close()
    error_exit("Wrong password, Please try again..")

bugz_comment = run_cmd('git request-pull %s %s %s' % (start_c, contrib_url, tag))
dbg_print(bugz_comment)

dbg_print("Trying to update bugzilla fields for bug %s" % bug_no)
update_bugz_fields(mvista_id, bugz_pword, bugz_comment)
print("Successfully posted the merge request on bugzilla. Done.")
