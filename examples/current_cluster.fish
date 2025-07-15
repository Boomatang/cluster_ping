# Defined via `source`
function current_cluster

  set -l delay 300

  set -l active (set_color magenta)
  set -l inactive (set_color black)
  set -l unknown (set_color yellow)
  set -l normal (set_color normal)

  set -l kubeconfig ~/.kube/config
  set -l prefix ''
  if test -n "$KUBECONFIG"
    set kubeconfig $KUBECONFIG
    set path (string split "/" -- $kubeconfig)
    set prefix $path[-2]/$path[-1]
  end

  if test ! -e $kubeconfig
    return 1
  end

  set -l context (yq '.current-context' $kubeconfig)
  set -l query '.contexts.[] | select(.name == "'$context'") | .context.cluster'
  set -l cluster (yq "$query" $kubeconfig)

  command cluster_ping check $kubeconfig $context &

  set -l result (cluster_ping validate $kubeconfig $context $delay)

  set -l result_list (string split ' ' $result)
  echo $result_list[1]
  echo $result_list[2]
  set color $unknown
  if test $result_list[2] = "recent=true"
    set color $inactive
    if test $result_list[1] = "connected=true"
      set color $active
    end
  end

  set -l resp $color$cluster$normal
  if test -n $prefix
    set resp $prefix $resp
  end

  echo $resp
end
