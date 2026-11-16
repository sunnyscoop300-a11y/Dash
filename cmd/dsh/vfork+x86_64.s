# dsh_vfork_exec(path, argv, envp, fds) — starts a program the way dash does:
# vfork() + dup2() + execve(), all in registers. The child never touches the
# stack (it shares memory with dsh until execve), so this has to be assembly.
# Returns the child's pid, or -errno if vfork failed. If execve fails, the
# child exits with 127.
	.text
	.global dsh_vfork_exec
	.type dsh_vfork_exec, @function
dsh_vfork_exec:
	mov	%rdi, %r8		# path
	mov	%rsi, %r9		# argv
	mov	%rdx, %r10		# envp
	mov	%rcx, %rdx		# fds: int[3], -1 = inherit
	mov	$58, %eax		# SYS_vfork
	syscall
	test	%rax, %rax
	jnz	3f			# parent (pid) or error (-errno)
	xor	%esi, %esi		# child: target fd 0, 1, 2
1:	movslq	(%rdx,%rsi,4), %rdi
	test	%rdi, %rdi
	js	2f
	mov	$33, %eax		# SYS_dup2(old = rdi, new = rsi)
	syscall
2:	inc	%esi
	cmp	$3, %esi
	jl	1b
	mov	%r8, %rdi
	mov	%r9, %rsi
	mov	%r10, %rdx
	mov	$59, %eax		# SYS_execve
	syscall
	mov	$127, %edi
	mov	$60, %eax		# SYS_exit
	syscall
3:	ret
	.size dsh_vfork_exec, .-dsh_vfork_exec
