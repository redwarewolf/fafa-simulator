using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using TMPro;

public class UIupdater : MonoBehaviour
{
    public TextMeshProUGUI cashTextBox;

    public GameMaster gameMaster;

    void Start(){
      cashTextBox = GameObject.FindWithTag("Cash").GetComponent<TextMeshProUGUI>();
    }

    public void updateUI(){
      cashTextBox.text = gameMaster.getPlayerCash().ToString();
    }

}
