using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using TMPro;

public class FootballPlayerCard : MonoBehaviour
{
    public FootballPlayer footballPlayer { get; set; }

    public void setPlayerCard(FootballPlayer aFootballPlayer){
        transform.Find("PlayerName").gameObject.GetComponent<TextMeshProUGUI>().text = aFootballPlayer.name;
        transform.Find("GKAbility").gameObject.GetComponent<TextMeshProUGUI>().text = "GK: " + aFootballPlayer.gkSkill.ToString();
        transform.Find("DefAbility").gameObject.GetComponent<TextMeshProUGUI>().text = "Def: " + aFootballPlayer.defSkill.ToString();
        transform.Find("MidAbility").gameObject.GetComponent<TextMeshProUGUI>().text = "Mid: " + aFootballPlayer.midSkill.ToString();
        transform.Find("AtkAbility").gameObject.GetComponent<TextMeshProUGUI>().text = "Atk: " + aFootballPlayer.atkSkill.ToString();

        footballPlayer= aFootballPlayer;
    } 
}
