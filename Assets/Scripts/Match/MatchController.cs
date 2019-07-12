﻿using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using TMPro;

public class MatchController : MonoBehaviour
{
  private float startTime;
  static public TextMeshProUGUI matchTextBox;
  static public TextMeshProUGUI timerTextBox;

  private int timeLeft;

  void Start(){
    startTime = Time.time;

    timerTextBox = GameObject.FindWithTag("Timer").GetComponent<TextMeshProUGUI>();
    matchTextBox = GameObject.FindWithTag("MatchText").GetComponent<TextMeshProUGUI>();
  }

  void Update(){
    timeLeft = 1 - (int)(Time.time - startTime);
    if(timeLeft == -1){
      startTime = Time.time;
      GameMaster.nextMatchEvent();
    }
    timerTextBox.text = timeLeft.ToString();

  }

  static public void updateMatchUI(Club currentBallHolder, int currentPosition){
    matchTextBox.text = ("The team " + currentBallHolder.getName() + " has the ball at position " + currentPosition.ToString());
  }
}
