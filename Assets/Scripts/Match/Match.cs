using System.Collections;
using System.Collections.Generic;
using System;
using UnityEngine;

public class Match : MonoBehaviour
{
  private Club myClub;

  private Club enemyClub;

  private int currentPosition = 50;
  private Club currentBallHolder = null;

  private int myClubScore;
  private int enemyClubScore;

  private int scoringChanceDividerConstant = 4;

  static private List<Event> randomEvents;

  private FootballPlayer currentPlayer;

  private FootballPlayer previousPlayer;
  private Club previousBallHolder;

  public Match(Club amyClub, Club aenemyClub){
    myClub = amyClub;
    enemyClub = aenemyClub;

    currentPlayer = null;
    previousPlayer = null;
    previousBallHolder = null;

    Debug.Log(amyClub.getName());
    Debug.Log(aenemyClub.getName());

    }

  public void nextMatchEvent(){

    // Verificar si algún equipo está en posición de meter gol
    if(teamScores()){
      return;
    }

    // Si no sucede ningún evento random o algún Gol, entonces calculo los eventos normales
    calculateNormalEvent();


    MatchController.updateMatchUI(currentBallHolder,currentPlayer, currentPosition, previousBallHolder, previousPlayer);
  }

  private bool teamScores(){
    //Si estoy en posición de tiro al arco y meto gol
    if (currentPosition >= 85 && currentBallHolder == myClub && RandomCalculator.evaluateChances(myClubScoreChance() / scoringChanceDividerConstant))
    {
        myClubScore++;

        MatchController.updateMatchScore(myClubScore.ToString() + "-" + enemyClubScore.ToString(), currentBallHolder.getName());
        currentBallHolder = enemyClub;
        currentPosition = 50;
        return true;
    }

    //Si el equipo contrario está en posición de tiro al arco y mete gol

    if (currentPosition <= 15 && currentBallHolder == enemyClub && RandomCalculator.evaluateChances(myClubStopChance() / scoringChanceDividerConstant))
    {
        enemyClubScore++;

        MatchController.updateMatchScore(myClubScore.ToString() + "-" + enemyClubScore.ToString(), currentBallHolder.getName());
        currentBallHolder = myClub;
        currentPosition = 50;
        return true;
    }
    return false;
  }

  private bool matchPositionIsDef(){
    return currentPosition <= 35;
  }
  private bool matchPositionIsMid(){
    return currentPosition > 35 &&  currentPosition <= 70;
  }
  private bool matchPositionIsAtk(){
    return currentPosition > 70;
  }

  private void calculateNormalEvent(){

    // Si la posición es en la defensa:
    if (matchPositionIsDef())
    {
      calculateGoalKeeper(myClubStopChance());
    }
    // Sino, si la posición es en el medio campo:
    else if (matchPositionIsMid())
    {
      calculateGoalKeeper(myClubMidFieldChance());
    }
    //Sino, como la posición es ataque:
    else
    {
      calculateGoalKeeper(myClubScoreChance());
    }
  }

  private void calculateGoalKeeper(int chancesToEvaluate){
    previousBallHolder = currentBallHolder;

    if (RandomCalculator.evaluateChances(chancesToEvaluate)){
        currentBallHolder = myClub;
        currentPosition = Math.Min(95, currentPosition + 10);
        calculateNewPlayer();
    }
    else
    {
        currentBallHolder = enemyClub;
        currentPosition = Math.Max(5, currentPosition - 10);
        calculateNewPlayer();
    }

    if (previousBallHolder.getName() == null)
    {
      Debug.Log("Previous Club == null");

      previousBallHolder = currentBallHolder;
    }
  }

  private void calculateNewPlayer(){
    previousPlayer = currentPlayer;

    Debug.Log("The Current currentBallHolder is: ");

    Debug.Log(currentBallHolder.getName());

    System.Random rnd = new System.Random();
    if (matchPositionIsAtk()) currentPlayer = currentBallHolder.attack[rnd.Next(currentBallHolder.attack.Count)];
    if (matchPositionIsDef()) currentPlayer = currentBallHolder.defense[rnd.Next(currentBallHolder.defense.Count)] ;
    if (matchPositionIsMid()) currentPlayer = currentBallHolder.midfielders[rnd.Next(currentBallHolder.midfielders.Count)];

    Debug.Log("The Current Player is: ");

    Debug.Log(currentPlayer.name);

    if(previousPlayer.name == null){
      Debug.Log("Previous player == null");
      Debug.Log("New PLayer is: " + currentPlayer.name);
      previousPlayer = currentPlayer;
    }
  }

  public int myClubMidFieldChance(){
    return (myClub.midfield() * 100) / (myClub.midfield() + enemyClub.midfield());
  }

  public int myClubScoreChance(){
    return (myClub.attacking() * 100) / (myClub.attacking() + enemyClub.defending() + enemyClub.goalkeeping());
  }

  public int myClubStopChance(){
    return ((myClub.defending() + myClub.goalkeeping()) * 100) / (myClub.defending() + myClub.goalkeeping() + enemyClub.attacking());
  }
}
