/**
 * @file
 * Copy-to-clipboard for the installer's environment-variable blocks.
 */
((Drupal, once) => {
  Drupal.behaviors.pantheonNextjsEnvCopy = {
    attach(context) {
      once('pntn-env-copy', '[data-pntn-copy]', context).forEach((button) => {
        button.addEventListener('click', () => {
          const target = document.getElementById(button.getAttribute('data-pntn-copy'));
          if (!target) {
            return;
          }
          const restore = () => {
            const label = button.textContent;
            button.textContent = Drupal.t('Copied');
            window.setTimeout(() => {
              button.textContent = label;
            }, 1500);
          };
          const selectText = () => {
            const range = document.createRange();
            range.selectNodeContents(target);
            const selection = window.getSelection();
            selection.removeAllRanges();
            selection.addRange(range);
          };
          if (navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(target.textContent).then(restore).catch(selectText);
          } else {
            selectText();
          }
        });
      });
    },
  };
})(Drupal, once);
