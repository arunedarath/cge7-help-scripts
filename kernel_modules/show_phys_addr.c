#include <linux/init.h>
#include <linux/module.h>
#include <linux/kobject.h>
#include <linux/sysfs.h>
#include <linux/mm.h>
#include <linux/sched.h>
#include <linux/hugetlb.h>


static struct kobject *vaddr_print_kobj;
static unsigned long vaddr;


static ssize_t vaddr_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
	return sprintf(buf, "%lx\n", virt_to_phys((void *)vaddr));
	return 0;
}

static void follow_pte(struct mm_struct * mm, unsigned long address, pte_t * entry)
{
	pgd_t * pgd = pgd_offset(mm, address);

	printk("follow_pte() for %lx\n", address);

	entry->pte = 0;
	if (!pgd_none(*pgd) && !pgd_bad(*pgd)) {
		pud_t * pud = pud_offset(pgd, address);
		struct vm_area_struct * vma = find_vma(mm, address);

		printk(" pgd = %lx\n", pgd_val(*pgd));

		if (pud_none(*pud)) {
			printk("  pud = empty\n");
			return;
		}
		if (pud_huge(*pud) && vma->vm_flags & VM_HUGETLB) {
			entry->pte = pud_val(*pud);
			printk("  pud = huge\n");
			return;
		}

		if (!pud_bad(*pud)) {
			pmd_t * pmd = pmd_offset(pud, address);

			printk("  pud = %lx\n", pud_val(*pud));

			if (pmd_none(*pmd)) {
				printk("   pmd = empty\n");
				return;
			}
			if (pmd_huge(*pmd) && vma->vm_flags & VM_HUGETLB) {
				entry->pte = pmd_val(*pmd);
				printk("   pmd = huge\n");
				return;
			}
			if (pmd_trans_huge(*pmd)) {
				entry->pte = pmd_val(*pmd);
				printk("   pmd = trans_huge\n");
				return;
			}
			if (!pmd_bad(*pmd)) {
				pte_t * pte = pte_offset_map(pmd, address);

				printk("   pmd = %lx\n", pmd_val(*pmd));

				if (!pte_none(*pte)) {
					entry->pte = pte_val(*pte);
					printk("    pte = %llx\n", pte_val(*pte));
				} else {
					printk("    pte = empty\n");
				}
				pte_unmap(pte);
			}
		}
	}
}


static ssize_t vaddr_store(struct kobject *kobj, struct kobj_attribute *attr, const char *buf, size_t count)
{
	int ret;
	struct mm_struct *mm = current->mm;
	pgd_t * pgd;
	pud_t * pud;
	pmd_t * pmd;
	pte_t * pte;
	pte_t  pte_e;


	ret = kstrtoul(buf, 16, &vaddr);
	if (ret)
		printk("failed to read vaddr\n");
	else {
		printk("vaddr is %lx\n", vaddr);
		printk("vaddr is vmalloc ? %d\n", is_vmalloc_addr((void *)vaddr));
		pgd = pgd_offset(mm, vaddr);
		if (pgd_none(*pgd))
			printk("not mapped in pgd\n");
		pud = pud_offset(pgd, vaddr);
		pmd = pmd_offset(pud, vaddr);
		pte = pte_offset_kernel(pmd, vaddr);
		printk("pgd_val = 0x%lx\n", pgd_val(*pgd));
		printk("pud_val = 0x%lx\n", pud_val(*pud));
		printk("pmd_val = 0x%lx\n", pmd_val(*pmd));
		printk("pte_val = 0x%llx\n", pte_val(*pte));
		printk("physical page = %llx\n", pte_val(*pte) & PAGE_MASK);
		follow_pte(current->mm, vaddr, &pte_e);
	}
	return count;
}


static struct kobj_attribute vaddr_print_attr =__ATTR(vaddr_print, 0660, &vaddr_show, &vaddr_store);

static int my_mode_init(void) {
	int error = 0;
	printk("Arun my_mode_init\n");
	vaddr_print_kobj = kobject_create_and_add("vaddr_print_kobj", kernel_kobj);
	if (!vaddr_print_kobj)
		return -ENOMEM;

	error = sysfs_create_file(vaddr_print_kobj, &vaddr_print_attr.attr);
	if (error)
		printk("failed to create vaddr_print_attr\n");

	return error;
}
module_init(my_mode_init);
