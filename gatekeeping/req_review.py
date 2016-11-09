#!/usr/bin/python3

from bs4 import BeautifulSoup as bs
import sys
import argparse
import subprocess
import getpass
import requests

bug_no = ''
revision = ''
p_count = ''
start = ''
start_c = ''

contrib = ''
msg = ''
contrib_url = ''
tag = ''
tmp_f = ''

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


def error_exit(prstr):
    print(prstr)
    print("Exiting..")
    sys.exit(1)


def execute_cmd(cmd, s_str, f_str):
    cmd_timeout = 180
    "Execute the bash commands encoded in cmd and handle timeouts"
    try:
        p = subprocess.Popen(cmd, shell=True)
        p.wait(timeout=cmd_timeout)
        if (p.returncode == 0):
            if (s_str):
                print (s_str)
        else:
            if (f_str):
                print(f_str)
            error_exit('The command:%s pid:%d failed' % (cmd, p.pid))
    except subprocess.TimeoutExpired:
        p.kill()
        print ("The command:%s pid:%d timed out, but continuing \n" % (cmd, p.pid))
        return


def find(lst, key, value):
    for i, dic in enumerate(lst):
        if dic[key] == value:
            return i
    return -1


def form_repo_data(idx, remote_branch):
    print("%s repo identified." % (repo_details[idx]['repo']))
    print("Your changes target the remote branch:%s" % (remote_branch))
    global contrib, msg, contrib_url, tag
    contrib = repo_details[idx]['pushto']
    contrib_url = repo_details[idx]['url']
    msg = 'Merge to %s' % (remote_branch)
    tag = '%s-%s-V%s' % (remote_branch, bug_no, revision)


def format_first_line(tfile):
    txt = open(tfile)
    tmp = txt.readline()
    txt.close()
    return tmp.splitlines()


def identify_repo():
    cmd = 'git config --get remote.origin.url > %s' % (tmp_f)
    execute_cmd(cmd, "", "Please make sure that you are inside a valid git repository")
    tmp = format_first_line(tmp_f)
    if (tmp):
        tmp = tmp[0].split('@')
        if (len(tmp) != 2):
            error_exit("Not an MV type repo\n")

        idx = find(repo_details, 'origin', tmp[1])
        if (idx == -1):
            error_exit("Unable to find the repo type\n")

        # Now identify the remote tracking branch of the current branch
        cmd = "git rev-parse --abbrev-ref --symbolic-full-name @{u} | cut -d'/' -f2- > %s" % (tmp_f)
        execute_cmd(cmd, "", "")
        tmp = format_first_line(tmp_f)
        if (len(tmp) != 0):
            form_repo_data(idx, tmp[0])
        else:
            error_exit("Unable to find the upstream branch for the current branch\n")
    else:
        error_exit("Not an MV type repo\n")


def mark_start_commit():
    global start_c
    if (p_count == 'None' and start == 'None'):
        error_exit("Please specify a start commit for making the merge request; use -s or -n")

    if (p_count != 'None'):
        start_c = 'HEAD~'+p_count
    elif (start != 'None'):
        start_c = start


def parse_args():
    global bug_no, revision, p_count, start, tmp_f
    parser = argparse.ArgumentParser(description='Perform merge request')
    parser.add_argument('-b', help='Bug number', required=True, type=int)
    parser.add_argument('-r', help='Patch revision', required=True, type=int)
    parser.add_argument('-n', help='No of patches you are pushing', required=False, type=int)
    parser.add_argument('-s', help='Start commit for merge request', required=False, type=str)
    args = vars(parser.parse_args())

    bug_no = str(args['b'])
    revision = str(args['r'])
    p_count = str(args['n'])
    start = str(args['s'])
    tmp_f = bug_no+'-V'+revision+'.file'


def check_err(err, got):
    if (err == got):
        error_exit(err)


def update_bugz_fields(uname, pword):
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

            txt = open(tmp_f)
            upd_d['comment'] = txt.read()
            txt.close()
            r = s.post(bugz_post_url, data=upd_d)
            print("Finished....... bye.")
        except requests.exceptions.Timeout:
            error_exit("Connection timed out")
        except requests.exceptions.RequestException as e:
            error_exit(e)




parse_args()
mark_start_commit()
identify_repo()

cmd = 'git tag -m "%s" "%s"' % (msg, tag)
success_str = 'Successfully created tag : %s\n' % (tag)
fail_str = 'Please try again after manually deleting the tag'
execute_cmd(cmd, success_str, fail_str)

print ("Pushing the tag : %s to %s" % (tag, contrib_url))
username = input("Please enter your bugzilla user name\n")
cmd = 'git push "%s"@"%s" "+%s"' % (username, contrib, tag)
success_str = 'Successfully pushed the tag to %s\n' % (contrib)
execute_cmd(cmd, success_str, "")

cmd = 'git request-pull %s %s %s | tee %s ; test ${PIPESTATUS[0]} -eq 0' % (start_c, contrib_url, tag, tmp_f)
success_str = 'Successfully generated pull request\n'
execute_cmd(cmd, success_str, "")

print ("Trying to update bugzilla fields for bug %s" % bug_no)
bugz_pword = getpass.getpass('Please enter your bugzilla password:')

update_bugz_fields(username, bugz_pword)
